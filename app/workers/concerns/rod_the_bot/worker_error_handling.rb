module RodTheBot
  module WorkerErrorHandling
    private

    def retry_job(error, **context)
      details = context.compact.map { |key, value| "#{key}=#{value}" }.join(" ")
      Rails.logger.error "#{self.class.name}: #{details} error=#{error.class} message=#{error.message}"
      raise error
    end
  end
end
