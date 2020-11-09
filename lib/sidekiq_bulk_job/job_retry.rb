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
      opts = default_setting.merge(options)
      queue_as = queue(@klass) || :default
      begin
        @handler.local(SidekiqBulkJob::BulkJob, opts, queue_as) do
          raise @exception
        end
      rescue Exception => e
      end
    end

    protected

    def default_setting
      # 0 retry: no retry and dead queue
      { 'class' => @klass.to_s, 'args' => @args, 'retry' => 0 }
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