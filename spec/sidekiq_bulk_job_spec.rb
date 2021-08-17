require 'logger'
require 'pry'

RSpec.describe SidekiqBulkJob do

  BATCH_SIZE = 30
  ASYNC_DELAY = 60
  SCHEDULED_DELAY = 5

  before :all do
    process_fail = lambda do |job_class_name, args, exception|
      # do somethine
      # send email
    end
    SidekiqBulkJob.config redis: Redis.new, logger: Logger.new(STDOUT), process_fail: process_fail, async_delay: ASYNC_DELAY, scheduled_delay: SCHEDULED_DELAY, queue: :test, batch_size: BATCH_SIZE, prefix: "SidekiqBulkJob"
  end

  before :each do
    scheduled.clear
    test_running.clear
    default_running.clear
    retry_set.clear
    redis.del SidekiqBulkJob.generate_key("TestJob")
  end

  let(:scheduled) {
    @scheduled ||= Sidekiq::ScheduledSet.new
  }

  let(:redis) {
    @redis ||= Redis.new
  }

  let(:test_running) {
    @test_running ||= Sidekiq::Queue.new("test")
  }

  let(:default_running) {
    @default_running ||= Sidekiq::Queue.new("default")
  }

  let(:retry_set) {
    @retry_set ||= Sidekiq::RetrySet.new
  }

  class TestJob
    include Sidekiq::Worker
    sidekiq_options queue: :default

    def perform(*args)
      puts args
    end
  end

  class TestMethod

    class << self
      def call(key, value)
        redis = Redis.new
        redis.set key, value
      end
    end

  end

  def load(args)
    SidekiqBulkJob::Utils.load(args)
  end

  it "run once perform_async" do
    SidekiqBulkJob.perform_async(TestJob, 10)

    expect(scheduled.size).to eq 1
    monitor = scheduled.find do |job|
      job.klass == 'SidekiqBulkJob::Monitor'
    end

    expect(monitor.nil?).to be false
    expect(monitor.at.between?(Time.now - 1, Time.now + ASYNC_DELAY)).to be true
    expect(monitor.queue).to eq "test"
    expect(monitor.args.size).to eq 2
    expect(monitor.args[1]).to eq "TestJob"

    result = SidekiqBulkJob.flush SidekiqBulkJob.generate_key("TestJob")
    expect(result.size).to eq 1
    expect(load(result[0])).to eq [10]
  end

  it "run #{BATCH_SIZE + 1} time in perform_async" do
    (BATCH_SIZE + 1).times do |i|
      SidekiqBulkJob.perform_async(TestJob, i)
    end

    expect(scheduled.size).to eq 1
    expect(test_running.size).to eq 1
    bulk_job = test_running.find do |job|
      job.klass == "SidekiqBulkJob::BulkJob"
    end
    expect(bulk_job.nil?).to be false
    expect(bulk_job.queue).to eq "test"
    expect(bulk_job.args.size).to eq 2
    expect(bulk_job.args[0]).to eq "TestJob"
    expect(bulk_job.args[1].size).to eq BATCH_SIZE

  end

  it "use perform_async with sidekiq job directly" do
    now = Time.now
    TestJob.batch_perform_async(9, 4, 10)
    expect(scheduled.size).to eq 1
    monitor = scheduled.find do |job|
      job.klass == 'SidekiqBulkJob::Monitor'
    end
    expect(monitor.nil?).to be false
    expect(monitor.at.between?(now - 1, now + ASYNC_DELAY + 1)).to be true
    # use same queue define in TestJob
    expect(monitor.queue).to eq "default"
    expect(monitor.args.size).to eq 2
    expect(monitor.args[1]).to eq "TestJob"

    result = SidekiqBulkJob.flush SidekiqBulkJob.generate_key("TestJob")
    expect(result.size).to eq 1
    expect(load(result[0])).to eq [9,4,10]
  end

  it "run #{BATCH_SIZE + 1} time with sidekiq job directly" do
    (BATCH_SIZE + 1).times do |i|
      TestJob.batch_perform_async(9, 4, 10)
    end

    expect(scheduled.size).to eq 1
    expect(default_running.size).to eq 1
    bulk_job = default_running.find do |job|
      job.klass == "SidekiqBulkJob::BulkJob"
    end
    expect(bulk_job.nil?).to be false
    expect(bulk_job.queue).to eq "default"
    expect(bulk_job.args.size).to eq 2
    expect(bulk_job.args[0]).to eq "TestJob"
    expect(bulk_job.args[1].size).to eq BATCH_SIZE

  end

  it "use once perform_at in further time" do
    at = Time.now + 60
    SidekiqBulkJob.perform_at(at, TestJob, 10)

    expect(scheduled.size).to eq 1
    scheduled_job = scheduled.find do |job|
      job.klass == 'SidekiqBulkJob::ScheduledJob'
    end

    expect(scheduled_job.nil?).to be false
    expect(scheduled_job.at.to_f == at.to_f).to be true
    expect(scheduled_job.queue).to eq "test"
    expect(scheduled_job.args.size).to eq 2
    expect(scheduled_job.args[0]).to eq "TestJob"

    result = SidekiqBulkJob.flush scheduled_job.args[1]
    expect(result.size).to eq 1
    expect(load(result[0])).to eq [10]

  end

  it "passing a before time variable in perform_at" do
    at = Time.now - 60
    SidekiqBulkJob.perform_at(at, TestJob, 10)

    expect(scheduled.size).to eq 1
    monitor = scheduled.find do |job|
      job.klass == 'SidekiqBulkJob::Monitor'
    end

    expect(monitor.nil?).to be false
  end

  it "use perform_in at 1 minute after" do
    now = Time.now
    SidekiqBulkJob.perform_in(1 * 60, TestJob, 10)
    expect(scheduled.size).to eq 1
    scheduled_job = scheduled.find do |job|
      job.klass == 'SidekiqBulkJob::ScheduledJob'
    end
    expect(scheduled_job.nil?).to be false
    expect(scheduled_job.at.between?(now, now + 61)).to be true
    expect(scheduled_job.queue).to eq "test"
    expect(scheduled_job.args.size).to eq 2
    expect(scheduled_job.args[0]).to eq "TestJob"

    result = SidekiqBulkJob.flush scheduled_job.args[1]
    expect(result.size).to eq 1
    expect(load(result[0])).to eq [10]
  end

  it "use perform_in after sleep 30 seconds" do
    now = Time.now
    SidekiqBulkJob.perform_in(1 * 60, TestJob, 10)
    SidekiqBulkJob.perform_in(1 * 60, TestJob, 11)

    expect(scheduled.size).to eq 1

    SidekiqBulkJob.perform_in(1 * 60 + SCHEDULED_DELAY + 1, TestJob, 12)
    expect(scheduled.size).to eq 2

    first_job = scheduled.find do |job|
      job.klass == 'SidekiqBulkJob::ScheduledJob' && job.at.between?(now, now + 61)
    end

    second_job = scheduled.find do |job|
      job.klass == 'SidekiqBulkJob::ScheduledJob' && job.at.between?(now + 59, now + 62 + SCHEDULED_DELAY)
    end

    expect(first_job.nil?).to be false
    expect(second_job.nil?).to be false

    expect(first_job.queue).to eq "test"
    expect(second_job.queue).to eq "test"

    result_1 = SidekiqBulkJob.flush first_job.args[1]
    expect(result_1.size).to eq 2
    expect(load(result_1[0])).to eq [10]
    expect(load(result_1[1])).to eq [11]

    result_2 = SidekiqBulkJob.flush second_job.args[1]
    expect(result_2.size).to eq 1
    expect(load(result_2[0])).to eq [12]
  end

  it "use batch_perform_at in further time" do
    at = Time.now + 60
    TestJob.batch_perform_at(at, 10)

    expect(scheduled.size).to eq 1
    scheduled_job = scheduled.find do |job|
      job.klass == 'SidekiqBulkJob::ScheduledJob'
    end

    expect(scheduled_job.nil?).to be false
    expect(scheduled_job.at.to_f == at.to_f).to be true
    expect(scheduled_job.queue).to eq "default"
    expect(scheduled_job.args.size).to eq 2
    expect(scheduled_job.args[0]).to eq "TestJob"

    result = SidekiqBulkJob.flush scheduled_job.args[1]
    expect(result.size).to eq 1
    expect(load(result[0])).to eq [10]
  end


  it "passing a before time variable in batch_perform_at" do
    at = Time.now - 60
    TestJob.batch_perform_at(at, 10)

    expect(scheduled.size).to eq 1
    monitor = scheduled.find do |job|
      job.klass == 'SidekiqBulkJob::Monitor'
    end

    expect(monitor.nil?).to be false
  end

  it "use batch_perform_in at 1 minute after" do
    now = Time.now
    TestJob.batch_perform_in(1 * 60, 10)
    expect(scheduled.size).to eq 1
    scheduled_job = scheduled.find do |job|
      job.klass == 'SidekiqBulkJob::ScheduledJob'
    end
    expect(scheduled_job.nil?).to be false
    expect(scheduled_job.at.between?(now - 1, now + 61)).to be true
    expect(scheduled_job.queue).to eq "default"
    expect(scheduled_job.args.size).to eq 2
    expect(scheduled_job.args[0]).to eq "TestJob"

    result = SidekiqBulkJob.flush scheduled_job.args[1]
    expect(result.size).to eq 1
    expect(load(result[0])).to eq [10]
  end


  it "use batch_perform_in after sleep 30 seconds" do
    now = Time.now
    TestJob.batch_perform_in(1 * 60, 10)
    TestJob.batch_perform_in(1 * 60, 11)

    expect(scheduled.size).to eq 1

    TestJob.batch_perform_in(90, 12)
    expect(scheduled.size).to eq 2

    first_job = scheduled.find do |job|
      job.klass == 'SidekiqBulkJob::ScheduledJob' && job.at.between?(now - 1, now + 61)
    end

    second_job = scheduled.find do |job|
      job.klass == 'SidekiqBulkJob::ScheduledJob' && job.at.between?(now + 60, now + 91)
    end

    expect(first_job.nil?).to be false
    expect(second_job.nil?).to be false

    expect(first_job.queue).to eq "default"
    expect(second_job.queue).to eq "default"

    result_1 = SidekiqBulkJob.flush first_job.args[1]
    expect(result_1.size).to eq 2
    expect(load(result_1[0])).to eq [10]
    expect(load(result_1[1])).to eq [11]

    result_2 = SidekiqBulkJob.flush second_job.args[1]
    expect(result_2.size).to eq 1
    expect(load(result_2[0])).to eq [12]
  end

  it "use setter in batch_perform_async" do
    now = Time.now
    TestJob.set(queue: :test).batch_perform_async(9, 4, 10)
    expect(scheduled.size).to eq 1
    monitor = scheduled.find do |job|
      job.klass == 'SidekiqBulkJob::Monitor'
    end
    expect(monitor.nil?).to be false
    expect(monitor.at.between?(now - 1, now + 61)).to be true
    # use same queue define in TestJob
    expect(monitor.queue).to eq "test"
    expect(monitor.args.size).to eq 2
    expect(monitor.args[1]).to eq "TestJob"

    result = SidekiqBulkJob.flush SidekiqBulkJob.generate_key("TestJob")
    expect(result.size).to eq 1
    expect(load(result[0])).to eq [9,4,10]

  end

  it "use setter set delay in batch_perform_async" do
    now = Time.now
    TestJob.set(queue: :test, in: 90).batch_perform_async(9, 4, 10)
    expect(scheduled.size).to eq 1
    scheduled_job = scheduled.find do |job|
      job.klass == 'SidekiqBulkJob::ScheduledJob' && job.at.between?(now + 60, now + 91)
    end
    expect(scheduled_job.nil?).to be false
    expect(scheduled_job.queue).to eq "test"
    expect(scheduled_job.args.size).to eq 2
    expect(scheduled_job.args[0]).to eq "TestJob"

    result = SidekiqBulkJob.flush scheduled_job.args[1]
    expect(result.size).to eq 1
    expect(load(result[0])).to eq [9,4,10]
  end

  it "use setter set delay in batch_perform_in" do
    now = Time.now
    # batch_perform_in first params interval will override 'in'/'at' option at setter
    TestJob.set(queue: :test, in: 90).batch_perform_in(10, 4, 10)
    expect(scheduled.size).to eq 1
    scheduled_job = scheduled.find do |job|
      job.klass == 'SidekiqBulkJob::ScheduledJob' && job.at.between?(now, now + 11)
    end
    expect(scheduled_job.nil?).to be false
    expect(scheduled_job.queue).to eq "test"
    expect(scheduled_job.args.size).to eq 2
    expect(scheduled_job.args[0]).to eq "TestJob"

    result = SidekiqBulkJob.flush scheduled_job.args[1]
    expect(result.size).to eq 1
    expect(load(result[0])).to eq [4,10]
  end


  it "push the failed job to the retry sidekiq queue" do
    args = [[1]]
    SidekiqBulkJob::BulkJob.new.perform(TestJob.to_s, args)
    expect(retry_set.size).to eq 1

    job = retry_set.select do |job|
      job.klass == SidekiqBulkJob::BulkJob.to_s
    end.first
    expect(job.nil?).to eq false
    expect(job.args).to eq args
  end

  it "run sidekiq bulk job and scheduled job use class method directly" do
    SidekiqBulkJob::BulkJob.new.perform("TestMethod.call", [ ["test001", 3].to_json])
    expect(retry_set.size).to eq 0
    expect(redis.get("test001")).to eq "3"
  end

  it "dump and load Hash with symbolize" do
    marshalled = SidekiqBulkJob::Utils.dump({jjid: "123", "klass" => "SomeWorker"})
    obj = SidekiqBulkJob::Utils.load marshalled
    expect(obj[:jjid]).to eq '123'
    expect(obj['jjid']).to eq nil
    expect(obj['klass']).to eq 'SomeWorker'

  end

end
