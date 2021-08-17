require "sidekiq"
require "sidekiq/job_retry"

require "sidekiq_bulk_job/utils"
require "sidekiq_bulk_job/bulk_error_handler"

module SidekiqBulkJob
  class JobRetry

    def initialize(klass, error_handle, options={})
      @handler = Sidekiq::JobRetry.new(options)
      @klass = klass
      @error_handle = error_handle
      @retry_count = 0
    end

    def push(options={})
      @retry_count = SidekiqBulkJob.redis.incr @error_handle.jid
      opts = job_options(options)
      queue_as = queue(@klass) || :default
      begin
        @handler.local(SidekiqBulkJob::BulkJob, opts, queue_as) do
          raise @error_handle.raise_error
        end
      rescue Exception => e
      end
    end

    protected

    def job_options(options={})
      # 0 retry: no retry and dead queue
      opts = {
        'class' => SidekiqBulkJob::BulkJob.to_s,
        'args' => @error_handle.args,
        'retry' => true,
        'retry_count' => @retry_count.to_i
      }.merge(options)
      if Sidekiq::VERSION >= "6.0.2"
        Sidekiq.dump_json(opts)
      else
        opts
      end
    end

    def queue(woker)
      if woker.included_modules.include?(Sidekiq::Worker) && !woker.sidekiq_options.nil? && !woker.sidekiq_options.empty?
        sidekiq_options = SidekiqBulkJob::Utils.symbolize_keys(woker.sidekiq_options)
        if !sidekiq_options[:queue].nil?
          sidekiq_options[:queue]
        end
      end
    end

  end
end