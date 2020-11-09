require "sidekiq"

require "sidekiq_bulk_job/utils"
require 'sidekiq/job_retry'

module SidekiqBulkJob
  class JobRetry

    def initialize(klass, args, exception, options={})
      @handler = Sidekiq::JobRetry.new(options)
      @klass = klass
      @args = args
      @exception = exception
    end

    def push(options={})
      opts = job_options(options)
      queue_as = queue(@klass) || :default
      begin
        @handler.local(SidekiqBulkJob::BulkJob, opts, queue_as) do
          raise @exception
        end
      rescue Exception => e
      end
    end

    protected

    def job_options(options={})
      # 0 retry: no retry and dead queue
      opts = { 'class' => @klass.to_s, 'args' => @args, 'retry' => 0 }.merge(options)
      if Sidekiq::VERSION >= "6.0.2"
        Sidekiq.dump_json(opts)
      else
        opts
      end
    end

    def queue(woker)
      if !woker.sidekiq_options.nil? && !woker.sidekiq_options.empty?
        sidekiq_options = Utils.symbolize_keys(woker.sidekiq_options)
        if !sidekiq_options[:queue].nil?
          sidekiq_options[:queue]
        end
      end
    end

  end
end