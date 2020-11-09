require "sidekiq"

module SidekiqBulkJob
  class ScheduledJob
    include Sidekiq::Worker
    sidekiq_options queue: :default, retry: false

    def perform(job_class_name, args_redis_key)
      job = job_class_name.constantize
      args_array = SidekiqBulkJob.flush args_redis_key
      args_array.each do |_args|
        begin
          args = JSON.parse _args
          job.new.send(:perform, *args)
        rescue Exception => e
          SidekiqBulkJob.logger.error("#{job_class_name} Args: #{args}, Error: #{e.full_message}")
          SidekiqBulkJob.fail_callback(job_class_name: job_class_name, args: args, exception: e)
          SidekiqBulkJob::JobRetry.new(job, args, e).push
        end
      end
    end
  end
end