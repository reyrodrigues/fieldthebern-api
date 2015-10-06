module GroundGame
  module Scenario
    class CreateVisit
      include Geokit::Geocoders

      def initialize(params, current_user)
        @params = params
        @current_user = current_user
      end

      def call
        visit = Visit.new(@params)
        visit.user = @current_user

        visit = correct_coordinates(visit)

        address = inferr_address(visit)


        address.result = visit.result
        address.save!

        visit.address = address

        visit.total_points = CreateScore.new(visit: visit).call

        visit
      end

      def validate_params(params)
        params = validate_coords(params)
        params
      end

      def correct_coordinates(visit)
        place = MultiGeocoder.reverse_geocode("#{visit.submitted_latitude} #{visit.submitted_longitude}")
        visit.corrected_latitude = place.lat
        visit.corrected_longitude = place.lng
        visit
      end

      def inferr_address(visit)
        # TODO: This is subject to change. Right now it,
        #   1. Tries to fetch via coordinates
        #   2. Tries to fetch via address
        #   3. Creates a new address if all else fails
        address = Address.find_by(longitude: visit.corrected_longitude, latitude: visit.corrected_latitude)
        address = Address.find_or_initialize_by(street_1: visit.submitted_street_1) unless address
        address
      end
    end
  end
end
