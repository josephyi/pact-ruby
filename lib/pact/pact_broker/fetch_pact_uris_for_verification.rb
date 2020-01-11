require 'pact/hal/entity'
require 'pact/hal/http_client'
require 'pact/provider/pact_uri'
require 'pact/errors'
require 'pact/pact_broker/fetch_pacts'

module Pact
  module PactBroker
    class FetchPactURIsForVerification
      attr_reader :provider, :consumer_version_selectors, :provider_version_tags, :broker_base_url, :http_client_options, :http_client, :options

      PACTS_FOR_VERIFICATION_RELATION = 'beta:provider-pacts-for-verification'.freeze
      PACTS = 'pacts'.freeze
      HREF = 'href'.freeze
      LINKS = '_links'.freeze
      SELF = 'self'.freeze
      EMBEDDED = '_embedded'.freeze

      def initialize(provider, consumer_version_selectors, provider_version_tags, broker_base_url, http_client_options, options = {})
        @provider = provider
        @consumer_version_selectors = consumer_version_selectors || []
        @provider_version_tags = provider_version_tags || []
        @http_client_options = http_client_options
        @broker_base_url = broker_base_url
        @http_client = Pact::Hal::HttpClient.new(http_client_options)
        @options = options
      end

      def self.call(provider, consumer_version_selectors, provider_version_tags, broker_base_url, http_client_options, options = {})
        new(provider, consumer_version_selectors, provider_version_tags, broker_base_url, http_client_options, options).call
      end

      def call
        if index.can?(PACTS_FOR_VERIFICATION_RELATION)
          log_message
          pacts_for_verification
        else
          # Fall back to old method of fetching pacts
          consumer_version_tags = consumer_version_selectors.collect{ | selector | selector[:tag] }
          FetchPacts.call(provider, consumer_version_tags, broker_base_url, http_client_options)
        end
      end

      private

      def index
        @index_entity ||= Pact::Hal::Link.new({ "href" => broker_base_url }, http_client).get.assert_success!
      end

      def pacts_for_verification
        pacts_for_verification_entity.response.body[EMBEDDED][PACTS].collect do | pact |
          metadata = {
            pending: pact["verificationProperties"]["pending"],
            notices: extract_notices(pact)
          }
          Pact::Provider::PactURI.new(pact[LINKS][SELF][HREF], http_client_options, metadata)
        end
      end

      def pacts_for_verification_entity
        index
          ._link(PACTS_FOR_VERIFICATION_RELATION)
          .expand(provider: provider)
          .post!(query)
      end

      def query
        q = {}
        q["includePendingStatus"] = true if options[:include_pending_status]
        q["consumerVersionSelectors"] = consumer_version_selectors if consumer_version_selectors.any?
        q["providerVersionTags"] = provider_version_tags if provider_version_tags.any?
        q
      end

      def extract_notices(pact)
        (pact["verificationProperties"]["notices"] || []).collect{ |notice| notice["text"] }.compact
      end

      def log_message
        latest = consumer_version_selectors.any? ? "" : "latest "
        message = "INFO: Fetching #{latest}pacts for #{provider} from #{broker_base_url}"
        if consumer_version_selectors.any?
          desc = consumer_version_selectors.collect do |selector|
            all_or_latest = selector[:all] ? "all" : "latest"
            # TODO support fallback
            name = selector[:fallback] ? "#{selector[:tag]} (or #{selector[:fallback]} if not found)" : selector[:tag]
            "#{all_or_latest} #{name}"
          end.join(", ")
          message << " for tags: #{desc}"
        end
        Pact.configuration.output_stream.puts message
      end
    end
  end
end
