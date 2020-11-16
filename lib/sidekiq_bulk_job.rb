require 'securerandom'
require "sidekiq"
require 'sidekiq/api'

require "sidekiq_bulk_job/version"
require "sidekiq_bulk_job/bulk_job"
require "sidekiq_bulk_job/monitor"
require "sidekiq_bulk_job/scheduled_job"
require "sidekiq_bulk_job/batch_runner"
require "sidekiq_bulk_job/utils"

module SidekiqBulkJob
  class Error < StandardError; end

  class Setter
    def initialize(opts)
      @opts = opts
    end

    def set(options)
      @opts.merge!(options)
      self
    end

    def perform_async(job_class, *args)
      options = SidekiqBulkJob::Utils.symbolize_keys(@opts)
      if options[:at].nil? && options[:in].nil?
        payload = {
            job_class_name: job_class.to_s,
            perfrom_args: args,
            queue: options[:queue] || SidekiqBulkJob.queue
          }.compact
        SidekiqBulkJob.process payload
      else
        perform_in(options[:at] || options[:in], job_class, *args)
      end
    end

    # +interval+ must be a timestamp, numeric or something that acts
    #   numeric (like an activesupport time interval).
    def perform_in(interval, job_class, *args)
      int = interval.to_f
      now = SidekiqBulkJob.time_now
      ts = (int < 1_000_000_000 ? now + int : int).to_f

      # Optimization to enqueue something now that is scheduled to go out now or in the past
      if ts > now.to_f
        options = SidekiqBulkJob::Utils.symbolize_keys(@opts)
        payload = {
          job_class_name: job_class.to_s,
          at: ts,
          perfrom_args: args,
          queue: options[:queue] || SidekiqBulkJob.queue
        }.compact
        SidekiqBulkJob.process payload
      else
        perform_async(job_class, *args)
      end
    end

    alias_method :perform_at, :perform_in
  end


  class << self

    attr_accessor :prefix, :redis, :queue, :batch_size, :logger, :process_fail

    def config(redis: , logger: , process_fail: , queue: :default, batch_size: 3000, prefix: "SidekiqBulkJob")
      if redis.nil?
        raise ArgumentError.new("redis not allow nil")
      end
      self.redis = redis
      self.queue = queue
      self.batch_size = batch_size
      self.prefix = prefix
      self.logger = logger
      self.process_fail = process_fail
    end

    def set(options)
      SidekiqBulkJob::Setter.new(options)
    end

    #
    # 无法定义具体执行时间，相当于perform_async的批量执行
    # example:
    #   SidekiqBulkJob.perform_async(SomeWorkerClass, *args)
    def perform_async(job_class, *perfrom_args)
      process(job_class_name: job_class.to_s, perfrom_args: perfrom_args)
      nil
    end

    # 延迟一段时间执行
    # example:
    #   SidekiqBulkJob.perform_at(Date.parse("2020-12-01"), SomeWorkerClass, *args)
    def perform_in(at, job_class, *perfrom_args)
      int = at.to_f
      now = time_now
      ts = (int < 1_000_000_000 ? now + int : int).to_f

      # Optimization to enqueue something now that is scheduled to go out now or in the past
      if ts <= now.to_f
        process(job_class_name: job_class.to_s, perfrom_args: perfrom_args)
      else
        process(at: ts, job_class_name: job_class.to_s, perfrom_args: perfrom_args)
      end
    end

    alias_method :perform_at, :perform_in


    def process(job_class_name: , at: nil, perfrom_args: [], queue: self.queue)
      if at.nil?
        key = generate_key(job_class_name)
        client.lpush key, SidekiqBulkJob::Utils.dump(perfrom_args)
        bulk_run(job_class_name, key, queue: queue) if need_flush?(key)
        monitor(job_class_name, queue: queue)
      else
        scheduled_set = Sidekiq::ScheduledSet.new
        args_redis_key = nil
        target = scheduled_set.find do |job|
          if job.klass == SidekiqBulkJob::ScheduledJob.to_s &&
                job.at.to_i.between?((at - 5).to_i, (at + 30).to_i) # 允许30秒延迟
              _job_class_name, args_redis_key = job.args
              _job_class_name == job_class_name
           end
        end
        if !target.nil? && !args_redis_key.nil? && !args_redis_key.empty?
          # 往现有的job参数set里增加参数
          client.lpush args_redis_key, SidekiqBulkJob::Utils.dump(perfrom_args)
        else
          # 新增加一个
          args_redis_key = SecureRandom.hex
          client.lpush args_redis_key, SidekiqBulkJob::Utils.dump(perfrom_args)
          SidekiqBulkJob::ScheduledJob.client_push("queue" => queue, "class" => SidekiqBulkJob::ScheduledJob, "at" => at, "args" => [job_class_name, args_redis_key])
        end
      end
    end

    def generate_key(job_class_name)
      "#{prefix}:#{job_class_name}"
    end

    def client
      if redis.nil?
        raise ArgumentError.new("Please initialize redis first!")
      end
      redis
    end

    def time_now
      Time.now
    end

    def need_flush?(key)
      count = client.llen key
      return true if count >= batch_size
    end

    def flush(key)
      result = []
      begin
        _result, success = client.multi do |multi|
          multi.lrange(key, 0, batch_size)
          multi.ltrim(key, batch_size+1, -1)
        end
        result += _result
        count = client.llen key
      end while count > 0
      clear(key)
      result.reverse
    end

    def clear(key)
      script = %Q{
        local size = redis.call('llen', KEYS[1])
        if size == 0 then redis.call('del', KEYS[1]) end
      }
      client.eval script, [key]
    end

    def bulk_run(job_class_name, key, queue: self.queue, async: true)
      args_array = flush(key)
      return if args_array.nil? || args_array.empty?
      async ? SidekiqBulkJob::BulkJob.client_push("queue" => queue, "class" => SidekiqBulkJob::BulkJob, "args" => [job_class_name, args_array]) : SidekiqBulkJob::BulkJob.new.perform(job_class_name, args_array)
    end

    def monitor(job_class_name, queue: self.queue)
      scheduled_set = Sidekiq::ScheduledSet.new
      _monitor = scheduled_set.find do |job|
        if job.klass == SidekiqBulkJob::Monitor.to_s
          timestamp, _job_class_name = job.args
          _job_class_name == job_class_name
        end
      end
      if !_monitor.nil?
        # TODO debug log
      else
        SidekiqBulkJob::Monitor.client_push("queue" => queue, "at" => (time_now + 60).to_f, "class" => SidekiqBulkJob::Monitor, "args" => [time_now.to_f, job_class_name])
      end
    end

    def fail_callback(job_class_name: , args:, exception: )
      process_fail.call(job_class_name, args, exception)
    end

  end



end
