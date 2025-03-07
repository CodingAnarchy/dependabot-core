# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "opentelemetry/sdk"

module Dependabot
  module OpenTelemetry
    extend T::Sig

    module Attributes
      JOB_ID = "dependabot.job.id"
      ERROR_TYPE = "dependabot.job.error_type"
      ERROR_DETAILS = "dependabot.job.error_details"
      METRIC = "dependabot.metric"
      BASE_COMMIT_SHA = "dependabot.base_commit_sha"
      DEPENDENCY_NAMES = "dependabot.dependency_names"
      PR_CLOSE_REASON = "dependabot.pr_close_reason"
    end

    sig { returns(T::Boolean) }
    def self.should_configure?
      ENV["OTEL_ENABLED"] == "true"
    end

    sig { void }
    def self.configure
      return unless should_configure?

      puts "OpenTelemetry is enabled, configuring..."

      require "opentelemetry/exporter/otlp"
      require "opentelemetry/instrumentation/excon"
      require "opentelemetry/instrumentation/faraday"
      require "opentelemetry/instrumentation/http"

      ::OpenTelemetry::SDK.configure do |config|
        config.service_name = "dependabot"
        config.use "OpenTelemetry::Instrumentation::Excon"
        config.use "OpenTelemetry::Instrumentation::Faraday"
        config.use "OpenTelemetry::Instrumentation::Http"
      end

      tracer
    end

    sig { returns(T.nilable(::OpenTelemetry::Trace::Tracer)) }
    def self.tracer
      return unless should_configure?

      ::OpenTelemetry.tracer_provider.tracer("dependabot", Dependabot::VERSION)
    end

    sig { void }
    def self.shutdown
      return unless should_configure?

      ::OpenTelemetry.tracer_provider.force_flush
      ::OpenTelemetry.tracer_provider.shutdown
    end

    sig do
      params(
        job_id: T.any(String, Integer),
        error_type: T.any(String, Symbol),
        error_details: T.nilable(T::Hash[T.untyped, T.untyped])
      ).void
    end
    def self.record_update_job_error(job_id:, error_type:, error_details:)
      return unless should_configure?

      current_span = ::OpenTelemetry::Trace.current_span

      attributes = {
        Attributes::JOB_ID => job_id,
        Attributes::ERROR_TYPE => error_type
      }

      error_details&.each do |key, value|
        attributes.store("#{Attributes::ERROR_DETAILS}.#{key}", value)
      end

      current_span.add_event(error_type, attributes: attributes)
    end

    sig do
      params(
        error: StandardError,
        job: T.untyped,
        tags: T::Hash[String, T.untyped]
      ).void
    end
    def self.record_exception(error:, job: nil, tags: {})
      return unless should_configure?

      current_span = ::OpenTelemetry::Trace.current_span

      current_span.set_attribute(Attributes::JOB_ID, job.id) if job
      current_span.add_attributes(tags) if tags.any?

      current_span.status = ::OpenTelemetry::Trace::Status.error(error.message)
      current_span.record_exception(error)
    end
  end
end
