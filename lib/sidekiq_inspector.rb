module SidekiqInspector
  class << self
    def queues
      Sidekiq::Queue.all.map do |queue|
        {
          name: queue.name,
          size: queue.size,
          latency: queue.latency.round(2)
        }
      end
    end

    def retries
      Sidekiq::RetrySet.new.map do |job|
        {
          jid: job.jid,
          class: job.klass,
          args: job.args,
          error: job.error_class,
          retry_count: job.retry_count,
          next_retry: job.at
        }
      end
    end

    def scheduled_jobs
      Sidekiq::ScheduledSet.new.map do |job|
        {
          jid: job.jid,
          class: job.klass,
          args: job.args,
          at: job.at
        }
      end
    end

    def errors
      Sidekiq::DeadSet.new.map do |job|
        {
          jid: job.jid,
          class: job.klass,
          args: job.args,
          error: job.error_class,
          error_message: job.error_message,
          failed_at: job.failed_at
        }
      end
    end

    def stats
      Sidekiq::Stats.new.to_json
    end

    def clear_all
      Sidekiq::Queue.all.each(&:clear)
      Sidekiq::RetrySet.new.clear
      Sidekiq::ScheduledSet.new.clear
      Sidekiq::DeadSet.new.clear
    end

    def retry_job(jid)
      job = find_job(jid)
      if job
        job.retry
        "Job #{jid} has been retried."
      else
        "Job #{jid} not found."
      end
    end

    def delete_job(jid)
      job = find_job(jid)
      if job
        job.delete
        "Job #{jid} has been deleted."
      else
        "Job #{jid} not found."
      end
    end

    private

    def find_job(jid)
      Sidekiq::RetrySet.new.find_job(jid) ||
        Sidekiq::ScheduledSet.new.find_job(jid) ||
        Sidekiq::DeadSet.new.find_job(jid) ||
        Sidekiq::Queue.all.flat_map { |q| q.find_job(jid) }.compact.first
    end
  end
end
