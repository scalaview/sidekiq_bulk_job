require "sidekiq"

module SidekiqBulkJob

  module BatchRunner

    module ClassMethods
      # 当使用sidekiq work的时候可以直接使用下面的方法，会把同类型的job汇总在1分钟内批量执行
      # 适合回调时候要执行的job，减少sidekiq job创建的数量，减少线程调度花费的时间
      # 缺点：job批量执行之后时间会比较久，但是比全部job分开执行时间要短

      # 批量异步执行
      def batch_perform_async(*args)
        SidekiqBulkJob.perform_async(self, *args)
      end

      # 批量确定时间异步执行
      def batch_perform_at(*args)
        SidekiqBulkJob.perform_at(self, *args)
      end

      # 批量延后一段时间执行
      def batch_perform_in(*args)
        SidekiqBulkJob.perform_in(self, *args)
      end
    end


    module Setter
      def batch_perform_async(*args)
        SidekiqBulkJob.set(@opts).perform_async(@klass, *args)
      end

      # 批量确定时间异步执行
      def batch_perform_in(interval, *args)
        SidekiqBulkJob.set(@opts).perform_at(interval, @klass, *args)
      end

      alias_method :batch_perform_at, :batch_perform_in

    end

  end

end


Sidekiq::Worker::ClassMethods.module_eval { include SidekiqBulkJob::BatchRunner::ClassMethods }

Sidekiq::Worker::Setter.class_eval { include SidekiqBulkJob::BatchRunner::Setter }