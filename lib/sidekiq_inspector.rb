require "sidekiq/api"

module SidekiqInspector
  class << self
    # List all Sidekiq queues with their size and latency
    def queues
      Sidekiq::Queue.all.map do |queue|
        {
          name: queue.name,
          size: queue.size,
          latency: queue.latency.round(2)
        }
      end
    end

    # List all jobs in the retry queue
    def retries
      Sidekiq::RetrySet.new.map do |job|
        {
          jid: job.jid,
          class: job.klass,
          args: job.args,
          error_class: job.item["error_class"],
          error_message: job.item["error_message"],
          retry_count: job.item["retry_count"],
          next_retry: parse_time(job.item["at"])
        }.compact
      end
    end

    # List all scheduled jobs
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

    # List all jobs in the dead queue (errors)
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

    # Get Sidekiq stats in a readable format
    def stats
      stats = Sidekiq::Stats.new
      {
        processed: stats.processed,
        failed: stats.failed,
        scheduled_size: stats.scheduled_size,
        retry_size: stats.retry_size,
        dead_size: stats.dead_size,
        processes_size: stats.processes_size,
        default_queue_latency: stats.default_queue_latency,
        workers_size: stats.workers_size,
        enqueued: stats.enqueued
      }
    end

    # Clear all Sidekiq queues, including retry, scheduled, and dead sets
    def clear_all
      Sidekiq::Queue.all.each(&:clear)
      Sidekiq::RetrySet.new.clear
      Sidekiq::ScheduledSet.new.clear
      Sidekiq::DeadSet.new.clear
    end

    # Retry a specific job by its JID
    # @param jid [String] The job ID to retry
    def retry_job(jid)
      job = find_job(jid)
      if job
        job.retry
        "Job #{jid} has been retried."
      else
        "Job #{jid} not found."
      end
    end

    # Delete a specific job by its JID
    # @param jid [String] The job ID to delete
    def delete_job(jid)
      job = find_job(jid)
      if job
        job.delete
        "Job #{jid} has been deleted."
      else
        "Job #{jid} not found."
      end
    end

    # List all recurring jobs defined in config/sidekiq.yml
    def recurring_jobs
      if defined?(Sidekiq::Scheduler)
        config_file = Rails.root.join("config", "sidekiq.yml")
        if File.exist?(config_file)
          yaml_content = YAML.load_file(config_file)
          schedule = yaml_content.dig(:scheduler, :schedule)
          if schedule.nil? || schedule.empty?
            "No recurring jobs found in config/sidekiq.yml. Make sure you have defined some in the :scheduler::schedule section."
          else
            schedule.map do |name, config|
              {
                name: name,
                class: config["class"],
                cron: config["cron"],
                every: config["every"],
                args: config["args"],
                queue: config["queue"],
                description: config["description"]
              }
            end
          end
        else
          "Sidekiq configuration file (config/sidekiq.yml) not found."
        end
      else
        "Sidekiq::Scheduler is not available. Make sure sidekiq-scheduler is installed and configured."
      end
    end

    # Display help information for all public methods
    def help
      puts "Available SidekiqInspector commands:"
      methods(false).sort.each do |method_name|
        next if method_name == :help

        method = method(method_name)
        doc = method.comment
        if doc
          description, *param_docs = doc.strip.split("\n")
          puts "  #{method_name}: #{description.strip}"
          if param_docs.any?
            param_docs.each do |param_doc|
              param, desc = param_doc.strip.match(/@param\s+(\w+)\s+\[[\w\[\]]+\]\s+(.+)/)&.captures
              puts "    - #{param}: #{desc}" if param && desc
            end
          end
        end
      end
      puts "\nUsage: SidekiqInspector.command_name"
      puts "For methods that require arguments, use: SidekiqInspector.command_name(arg1, arg2, ...)"
    end

    # Inspect a specific queue by name
    # @param queue_name [String] The name of the queue to inspect
    def inspect_queue(queue_name)
      queue = Sidekiq::Queue.new(queue_name)
      {
        name: queue.name,
        size: queue.size,
        latency: queue.latency.round(2),
        jobs: queue.map do |job|
          {
            jid: job.jid,
            class: job.klass,
            args: job.args,
            enqueued_at: job.enqueued_at
          }
        end
      }
    end

    # Pause or unpause a specific queue
    # @param queue_name [String] The name of the queue to pause or unpause
    # @param pause [Boolean] True to pause, false to unpause
    def toggle_queue_pause(queue_name, pause)
      queue = Sidekiq::Queue.new(queue_name)
      if pause
        queue.pause!
        "Queue #{queue_name} has been paused."
      else
        queue.unpause!
        "Queue #{queue_name} has been unpaused."
      end
    end

    # Search for jobs across all queues
    # @param search_term [String] The term to search for in job class names or arguments
    def search_jobs(search_term)
      results = []
      Sidekiq::Queue.all.each do |queue|
        queue.each do |job|
          if job.klass.downcase.include?(search_term.downcase) || job.args.to_s.downcase.include?(search_term.downcase)
            results << {
              queue: queue.name,
              jid: job.jid,
              class: job.klass,
              args: job.args
            }
          end
        end
      end
      results
    end

    # Get information about current Sidekiq processes
    def processes
      Sidekiq::ProcessSet.new.map do |process|
        {
          identity: process["identity"],
          started_at: Time.at(process["started_at"]),
          queues: process["queues"],
          labels: process["labels"],
          concurrency: process["concurrency"],
          busy: process["busy"]
        }
      end
    end

    private

    def find_job(jid)
      Sidekiq::RetrySet.new.find_job(jid) ||
        Sidekiq::ScheduledSet.new.find_job(jid) ||
        Sidekiq::DeadSet.new.find_job(jid) ||
        Sidekiq::Queue.all.flat_map { |q| q.find_job(jid) }.compact.first
    end

    def parse_time(timestamp)
      return nil if timestamp.nil?

      Time.at(timestamp.to_f)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
