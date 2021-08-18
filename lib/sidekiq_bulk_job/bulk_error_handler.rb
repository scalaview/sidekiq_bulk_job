module SidekiqBulkJob
  class BulkErrorHandler

    ErrorCollection = Struct.new(:args, :exception) do
      def message
        exception.message
      end

      def backtrace
        exception.backtrace
      end
    end

    attr_accessor :job_class_name, :errors, :jid

    def initialize(job_class_name, jid)
      @jid = jid || SecureRandom.hex(12)
      @job_class_name = job_class_name
      @errors = []
    end

    def add(job_args, exception)
      errors << ErrorCollection.new(job_args, exception)
    end

    def backtrace
      errors.map(&:backtrace).flatten
    end

    def args
      [job_class_name, errors.map(&:args)]
    end

    def failed?
      !errors.empty?
    end

    def raise_error
      error = BulkError.new(errors.map(&:message).join('; '))
      error.set_backtrace self.backtrace
      error
    end

    def retry_count
      SidekiqBulkJob.redis.incr jid
    end

    def clear
      SidekiqBulkJob.redis.del jid
    end

    class BulkError < StandardError
      def initialize(message)
        super(message)
      end
    end

  end
end