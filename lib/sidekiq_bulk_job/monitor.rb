require "sidekiq"

module SidekiqBulkJob
  class Monitor
    include Sidekiq::Worker
    sidekiq_options queue: :default, retry: false

    def perform(timestamp, job_class_name)
      SidekiqBulkJob.bulk_run(job_class_name, SidekiqBulkJob.generate_key(job_class_name), async: false)
    end
  end
end