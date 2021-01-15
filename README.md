# SidekiqBulkJob

A tool to collect the same class jobs together and running in batch.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sidekiq_bulk_job'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install sidekiq_bulk_job

## Usage

### Initialization：

##### Parameters：

* redis: redis client.
* logger: log object，default Logger.new(STDOUT).
* process_fail: a callback when the job fail.
* async_delay: await delay time，default 60 seconds.
* scheduled_delay: scheduled job delay time，default 10 seconds.
* queue: default sidekiq running queue. By default the batch job will run at queue as same as sidekiq worker defined.
* batch_size: batch size in same job，default 3000.
* prefix: redis key prefix, default SidekiqBulkJob.

```ruby
	process_fail = lambda do |job_class_name, args, exception|
	# do something
	# send email
	end
	SidekiqBulkJob.config({
		redis: Redis.new,
		logger: Logger.new(STDOUT),
		process_fail: process_fail,
		async_delay: ASYNC_DELAY,
		scheduled_delay: SCHEDULED_DELAY,
		queue: :test,
		batch_size: BATCH_SIZE,
		prefix: "SidekiqBulkJob"
	})
	  // push a job
	SidekiqBulkJob.perform_async(TestJob, 10)
```

### Usage

At first define a TestJob as example
```ruby
# create a sidekiq worker, use default queue
  class TestJob
    include Sidekiq::Worker
    sidekiq_options queue: :default

    def perform(*args)
      puts args
    end
  end
  ```
  
##### Use SidekiqBulkJob async

  SidekiqBulkJob will collect the same job in to a list, a batch job will create when beyond the ```batch_size``` in  ```async_delay``` amount, and clear the list. The list will continue to collect the job which pushing inside. If reach the```async_delay``` time, the SidekiqBulkJob will also created to finish all job collected.
  
```ruby
# create a sidekiq worker, use default queue
  class TestJob
    include Sidekiq::Worker
    sidekiq_options queue: :default

    def perform(*args)
      puts args
    end
  end

  # simple use
  SidekiqBulkJob.perform_async(TestJob, 10)

  # here will not create 1001 job in sidekiq
  # now there are tow jobs created, one is collected 1000 TestJob in batch, another has 1 job inside.
  (BATCH_SIZE + 1).times do |i|
      SidekiqBulkJob.perform_async(TestJob, i)
  end
```

##### Use SidekiqWork batch_perform_async to run async task

```ruby
# same as SidekiqBulkJob.perform_async(TestJob, 10)
TestJob.batch_perform_async(10)
```

##### Use SidekiqBulkJob perform_at/perform_in to set scheduled task

```ruby
# run at 1 minute after with single job
SidekiqBulkJob.perform_at(1.minutes.after, TestJob, 10)
# same as below
SidekiqBulkJob.perform_in(1 * 60, TestJob, 10)
```

##### Use SidekiqWork batch_perform_at/batch_perform_in to set scheduled task

```ruby
# same as SidekiqBulkJob.perform_at(1.minutes.after, TestJob, 10)
TestJob.batch_perform_at(1.minutes.after, 10)
# same as SidekiqBulkJob.perform_in(1 * 60, TestJob, 10)
TestJob.batch_perform_in(1.minute, 10)
```

##### Use setter to set task

```ruby
# set queue to test and run async
TestJob.set(queue: :test).batch_perform_async(10)
# set queue to test and run after 90 seconds
TestJob.set(queue: :test, in: 90).batch_perform_async(10)

#batch_perform_in first params interval will be overrided 'in'/'at' option at setter
# run after 90 seconds instead of 10 seconds
TestJob.set(queue: :test, in: 90).batch_perform_in(10, 10)
```

## 中文

### 初始化：

##### 参数：

* redis: redis client
* logger: 日志对象，默认Logger.new(STDOUT)
* process_fail: 当job处理失败的通用回调
* async_delay: 延迟等待时间，默认60秒
* scheduled_delay: 定时任务延迟时间，默认10秒
* queue: 默认运行队列。根据job本身设置的队列运行，当没有设置时候就使用这里设置的队列运行
* batch_size: 同种类型job批量运行数量，默认3000
* prefix: 存储到redis的前缀，默认SidekiqBulkJob

```ruby
	process_fail = lambda do |job_class_name, args, exception|
	# do something
	# send email
	end
	SidekiqBulkJob.config({
		redis: Redis.new,
		logger: Logger.new(STDOUT),
		process_fail: process_fail,
		async_delay: ASYNC_DELAY,
		scheduled_delay: SCHEDULED_DELAY,
		queue: :test,
		batch_size: BATCH_SIZE,
		prefix: "SidekiqBulkJob"
	})
	  // push a job
	SidekiqBulkJob.perform_async(TestJob, 10)
```

### 用法

设置一个TestJob举例子
```ruby
# create a sidekiq worker, use default queue
  class TestJob
    include Sidekiq::Worker
    sidekiq_options queue: :default

    def perform(*args)
      puts args
    end
  end
  ```
  
##### 使用SidekiqBulkJob的async接口

SidekiqBulkJob会把同类型的job汇总到一个list中，当```async_delay```时间内超过```batch_size```，会新建一个batch job立刻执行汇总的全部jobs，清空list，清空的list会继续收集后续推入的job；如果在```async_delay```时间内未到达```batch_size```则会在最后一个job推入后等待```async_delay```时间创建一个batch job执行汇总的全部jobs
```ruby
# create a sidekiq worker, use default queue
  class TestJob
    include Sidekiq::Worker
    sidekiq_options queue: :default

    def perform(*args)
      puts args
    end
  end

  # simple use
  SidekiqBulkJob.perform_async(TestJob, 10)

  # here will not create 1001 job in sidekiq
  # now there are tow jobs created, one is collected 1000 TestJob in batch, another has 1 job inside.
  (BATCH_SIZE + 1).times do |i|
      SidekiqBulkJob.perform_async(TestJob, i)
  end
```

##### 使用SidekiqWork的batch_perform_async接口异步执行任务

```ruby
# same as SidekiqBulkJob.perform_async(TestJob, 10)
TestJob.batch_perform_async(10)
```

##### 使用SidekiqBulkJob的perform_at/perform_in接口设置定时任务

```ruby
# run at 1 minute after with single job
SidekiqBulkJob.perform_at(1.minutes.after, TestJob, 10)
# same as below
SidekiqBulkJob.perform_in(1 * 60, TestJob, 10)
```

##### 使用SidekiqWork的batch_perform_at/batch_perform_in接口设置定时任务

```ruby
# same as SidekiqBulkJob.perform_at(1.minutes.after, TestJob, 10)
TestJob.batch_perform_at(1.minutes.after, 10)
# same as SidekiqBulkJob.perform_in(1 * 60, TestJob, 10)
TestJob.batch_perform_in(1.minute, 10)
```

##### 使用setter设置

```ruby
# set queue to test and run async
TestJob.set(queue: :test).batch_perform_async(10)
# set queue to test and run after 90 seconds
TestJob.set(queue: :test, in: 90).batch_perform_async(10)

#batch_perform_in first params interval will be overrided 'in'/'at' option at setter
# run after 90 seconds instead of 10 seconds
TestJob.set(queue: :test, in: 90).batch_perform_in(10, 10)
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/scalaview/sidekiq_bulk_job. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/scalaview/sidekiq_bulk_job/blob/master/CODE_OF_CONDUCT.md).


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the SidekiqBulkJob project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/scalaview/sidekiq_bulk_job/blob/master/CODE_OF_CONDUCT.md).
