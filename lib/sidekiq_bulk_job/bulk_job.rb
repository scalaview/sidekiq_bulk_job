require "sidekiq"

require "sidekiq_bulk_job/job_retry"
require "sidekiq_bulk_job/bulk_error_handler"
require "sidekiq_bulk_job/utils"

module SidekiqBulkJob
  class BulkJob
    include Sidekiq::Worker
    sidekiq_options queue: :default, retry: true

    def perform(job_class_name, args_array)
      target_name, method_name = SidekiqBulkJob::Utils.split_class_name_with_method job_class_name
      job = SidekiqBulkJob::Utils.constantize(target_name)
      error_handle = BulkErrorHandler.new(job_class_name, self.jid)
      args_array.each do |_args|
        begin
          args = SidekiqBulkJob::Utils.load _args
          if SidekiqBulkJob::Utils.class_with_method?(job_class_name)
            job.send(method_name, *args)
          else
            job.new.send(method_name, *args)
          end
        rescue Exception => e
          error_handle.add _args, e
          SidekiqBulkJob.logger.error("#{job_class_name} Args: #{args}, Error: #{e.respond_to?(:full_message) ? e.full_message : e.message}")
        end
      end
      if error_handle.failed?
        SidekiqBulkJob.fail_callback(job_class_name: job_class_name, args: error_handle.args, exception: error_handle.raise_error)
        SidekiqBulkJob::JobRetry.new(job, error_handle).push
      else
        error_handle.clear
      end
    end
  end
end