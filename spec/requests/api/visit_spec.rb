require "rails_helper"

describe "Visit API" do
  describe "POST /visits" do
    it "requires authentication" do
      post "#{host}/visits"
      expect(last_response.status).to eq 401
      expect(json).to be_a_valid_json_api_error.with_id "NOT_AUTHORIZED"
    end

    context "when authenticated" do
      let(:token) { authenticate(email: "test-user@mail.com", password: "password") }

      before do
        @user = create(:user, id: 11, email: "test-user@mail.com", password: "password", state_code: "NY")
      end

      context "when it succeeds creating the visit" do
        it "should return the created visit, with score included" do
          create(:address, id: 1)

          authenticated_post "visits", {
            data: {
              attributes: { duration_sec: 200 },
            },
            included: [ { id: 1, type: "addresses" } ]
          }, token

          expect(last_response.status).to eq 200

          visit_json = json.data.attributes

          expect(visit_json.duration_sec).to eq 200
          expect(visit_json.total_points).not_to be_nil

          included_json = json.included
          scores_json = included_json.select { |include| include.type == "scores" }
          expect(scores_json.length).to eq 1
          score_json = scores_json.first.attributes
          expect(score_json.points_for_updates).to eq 0
          expect(score_json.points_for_knock).to eq 5
        end

        it "should update the user's total score" do
          Sidekiq::Testing.inline! do
            create(:address, id: 1)

            expect(@user.total_points).to eq 0

            authenticated_post "visits", {
              data: {
                attributes: { duration_sec: 200 },
              },
              included: [ { id: 1, type: "addresses" } ]
            }, token

            expect(@user.reload.total_points).to eq 5
          end
        end

        it "should update the 'everyone' leaderboard" do
          Sidekiq::Testing.inline! do
            create(:address, id: 1)

            expect(@user.total_points).to eq 0

            authenticated_post "visits", {
              data: {
                attributes: { duration_sec: 200 },
              },
              included: [ { id: 1, type: "addresses" } ]
            }, token

            rankings = Ranking.for_everyone(id: @user.id)
            expect(rankings.length).to eq 1
            expect(rankings.first.user).to eq @user
            expect(rankings.first.score).to eq 5.0
          end
        end

        it "should update the 'state' leaderboard" do
          Sidekiq::Testing.inline! do
            create(:address, id: 1)

            expect(@user.total_points).to eq 0

            authenticated_post "visits", {
              data: {
                attributes: { duration_sec: 200 },
              },
              included: [ { id: 1, type: "addresses" } ]
            }, token

            rankings = Ranking.for_state(id: @user.id, state_code: "NY")
            expect(rankings.length).to eq 1
            expect(rankings.first.user).to eq @user
            expect(rankings.first.score).to eq 5.0
          end
        end

        it "should update the 'friends' leaderboard" do
          Sidekiq::Testing.inline! do
            create(:address, id: 1)

            expect(@user.total_points).to eq 0

            authenticated_post "visits", {
              data: {
                attributes: { duration_sec: 200 },
              },
              included: [ { id: 1, type: "addresses" } ]
            }, token

            rankings = Ranking.for_user_in_users_friend_list(user: @user)
            expect(rankings.length).to eq 1
            expect(rankings.first.user).to eq @user
            expect(rankings.first.score).to eq 5.0
          end
        end

        context "when address exists" do

          context "when person already exists" do

            it "creates a visit, updates the address and the person" do
              address = create(:address, id: 1)
              create(:person,
                id: 10,
                address: address,
                canvass_response: :unknown,
                party_affiliation: :unknown_affiliation,
                previously_participated_in_caucus_or_primary: false)

              authenticated_post "visits", {
                data: {
                  attributes: { duration_sec: 200 },
                },
                included: [
                  {
                    type: "addresses",
                    id: 1,
                    attributes: {
                      latitude: 2.0,
                      longitude: 3.0,
                      city: "New York",
                      state_code: "NY",
                      zip_code: "12345",
                      street_1: "Test street",
                      street_2: "Additional data"
                    }
                  },
                  {
                    type: "people",
                    id: 10,
                    attributes: {
                      first_name: "John",
                      last_name: "Doe",
                      canvass_response: "leaning_for",
                      party_affiliation: "democrat_affiliation",
                      email: "john@doe.com",
                      phone: "555-555-1212",
                      preferred_contact_method: "phone",
                      previously_participated_in_caucus_or_primary: true
                    }
                  }
                ]
              }, token

              expect(last_response.status).to eq 200

              expect(Person.count).to eq 1
              expect(Address.count).to eq 1

              modified_address = Address.find(1)
              expect(modified_address.latitude).to eq 2.0
              expect(modified_address.longitude).to eq 3.0
              expect(modified_address.city).to eq "New York"
              expect(modified_address.state_code).to eq "NY"
              expect(modified_address.zip_code).to eq "12345"
              expect(modified_address.street_1).to eq "Test street"
              expect(modified_address.street_2).to eq "Additional data"

              modified_person = Person.find(10)
              expect(modified_person.first_name).to eq "John"
              expect(modified_person.last_name).to eq "Doe"
              expect(modified_person.leaning_for?).to be true
              expect(modified_person.democrat_affiliation?).to be true
              expect(modified_person.email).to eq "john@doe.com"
              expect(modified_person.phone).to eq "555-555-1212"
              expect(modified_person.contact_by_phone?).to be true
              expect(modified_person.previously_participated_in_caucus_or_primary?).to be true

              expect(modified_person.address).to eq modified_address
              expect(modified_address.most_supportive_resident).to eq modified_person
              expect(modified_address.best_canvass_response).to eq modified_person.canvass_response
              expect(modified_address.last_canvass_response).to eq modified_person.canvass_response
            end

            it "does not override nil values for some fields" do
              address = create(:address, id: 1)
              create(:person,
                id: 10,
                address: address,
                canvass_response: :unknown,
                party_affiliation: :unknown_affiliation,
                email: "john@doe.com",
                phone: "555-555-1212",
                preferred_contact_method: "phone",
                previously_participated_in_caucus_or_primary: false)

              authenticated_post "visits", {
                data: {
                  attributes: { duration_sec: 200 },
                },
                included: [
                  {
                    type: "addresses",
                    id: 1,
                    attributes: {
                      latitude: 2.0,
                      longitude: 3.0,
                      city: "New York",
                      state_code: "NY",
                      zip_code: "12345",
                      street_1: "Test street",
                      street_2: "Additional data"
                    }
                  },
                  {
                    type: "people",
                    id: 10,
                    attributes: {
                      first_name: "John",
                      last_name: "Doe",
                      canvass_response: "leaning_for",
                      party_affiliation: "democrat_affiliation",
                      email: nil,
                      phone: nil,
                      preferred_contact_method: nil,
                      previously_participated_in_caucus_or_primary: nil
                    }
                  }
                ]
              }, token

              expect(last_response.status).to eq 200

              expect(Person.count).to eq 1
              expect(Address.count).to eq 1

              modified_person = Person.find(10)
              expect(modified_person.first_name).to eq "John"
              expect(modified_person.last_name).to eq "Doe"
              expect(modified_person.leaning_for?).to be true
              expect(modified_person.democrat_affiliation?).to be true
              expect(modified_person.email).to eq "john@doe.com"
              expect(modified_person.phone).to eq "555-555-1212"
              expect(modified_person.contact_by_phone?).to be true
              expect(modified_person.previously_participated_in_caucus_or_primary?).to be false
            end
          end

          context "when person does not exist" do

            it "creates a visit, updates the address, creates the person" do

              address = create(:address, id: 1)

              authenticated_post "visits", {
                data: {
                  attributes: { duration_sec: 200 },
                },
                included: [
                  {
                    type: "addresses",
                    id: 1,
                    attributes: {
                      latitude: 2.0,
                      longitude: 3.0,
                      city: "New York",
                      state_code: "NY",
                      zip_code: "12345",
                      street_1: "Test street",
                      street_2: "Additional data"
                    }
                  },
                  {
                    type: "people",
                    attributes: {
                      first_name: "John",
                      last_name: "Doe",
                      canvass_response: "leaning_for",
                      party_affiliation: "democrat_affiliation",
                      email: "john@doe.com",
                      phone: "555-555-1212",
                      preferred_contact_method: "phone",
                      previously_participated_in_caucus_or_primary: true
                    }
                  }
                ]
              }, token

              expect(last_response.status).to eq 200
              expect(json.data.relationships.people.length).to eq 1

              expect(Person.count).to eq 1
              expect(Address.count).to eq 1

              modified_address = Address.find(1)
              expect(modified_address.latitude).to eq 2.0
              expect(modified_address.longitude).to eq 3.0
              expect(modified_address.city).to eq "New York"
              expect(modified_address.state_code).to eq "NY"
              expect(modified_address.zip_code).to eq "12345"
              expect(modified_address.street_1).to eq "Test street"
              expect(modified_address.street_2).to eq "Additional data"

              new_person = Person.last
              expect(new_person.first_name).to eq "John"
              expect(new_person.last_name).to eq "Doe"
              expect(new_person.leaning_for?).to be true
              expect(new_person.democrat_affiliation?).to be true
              expect(new_person.email).to eq "john@doe.com"
              expect(new_person.phone).to eq "555-555-1212"
              expect(new_person.contact_by_phone?).to be true
              expect(new_person.previously_participated_in_caucus_or_primary?).to be true

              expect(new_person.address).to eq modified_address
              expect(modified_address.most_supportive_resident).to eq new_person
              expect(modified_address.best_canvass_response).to eq new_person.canvass_response
              expect(modified_address.last_canvass_response).to eq new_person.canvass_response
            end
          end

          context "when some people exist, some don't" do

            it "creates a visit, updates the address, creates people that don't exist, updates people that do" do
              address = create(:address, id: 1)
              create(:person, id: 10, address: address, canvass_response: :unknown, party_affiliation: :unknown_affiliation)

              authenticated_post "visits", {
                data: {
                  attributes: { duration_sec: 200 }
                },
                included: [
                  {
                    type: "addresses",
                    id: 1,
                    attributes: {
                      latitude: 2.0,
                      longitude: 3.0,
                      city: "New York",
                      state_code: "NY",
                      zip_code: "12345",
                      street_1: "Test street",
                      street_2: "Additional data"
                    }
                  },
                  {
                    type: "people",
                    id: 10,
                    attributes: {
                      first_name: "John",
                      last_name: "Doe",
                      canvass_response: "leaning_for",
                      party_affiliation: "democrat_affiliation",
                      email: "john@doe.com",
                      phone:"555-555-1212",
                      preferred_contact_method: "phone",
                      previously_participated_in_caucus_or_primary: true
                    }
                  },
                  {
                    type: "people",
                    attributes: {
                      first_name: "Jane",
                      last_name: "Doe",
                      canvass_response: "strongly_for",
                      party_affiliation: "republican_affiliation",
                      email: "jane@doe.com",
                      phone: "555-555-1212",
                      preferred_contact_method: "email",
                      previously_participated_in_caucus_or_primary: true
                    }
                  }
                ]
              }, token

              expect(last_response.status).to eq 200

              expect(Person.count).to eq 2
              expect(Address.count).to eq 1

              modified_address = Address.find(1)
              expect(modified_address.latitude).to eq 2.0
              expect(modified_address.longitude).to eq 3.0
              expect(modified_address.city).to eq "New York"
              expect(modified_address.state_code).to eq "NY"
              expect(modified_address.zip_code).to eq "12345"
              expect(modified_address.street_1).to eq "Test street"
              expect(modified_address.street_2).to eq "Additional data"

              modified_person = Person.find(10)
              expect(modified_person.first_name).to eq "John"
              expect(modified_person.last_name).to eq "Doe"
              expect(modified_person.leaning_for?).to be true
              expect(modified_person.democrat_affiliation?).to be true
              expect(modified_person.email).to eq "john@doe.com"
              expect(modified_person.phone).to eq "555-555-1212"
              expect(modified_person.contact_by_phone?).to be true
              expect(modified_person.previously_participated_in_caucus_or_primary?).to be true

              new_person = Person.find_by(first_name: "Jane")
              expect(new_person).to be_persisted
              expect(new_person.last_name).to eq "Doe"
              expect(new_person.strongly_for?).to be true
              expect(new_person.republican_affiliation?).to be true
              expect(new_person.email).to eq "jane@doe.com"
              expect(new_person.phone).to eq "555-555-1212"
              expect(new_person.contact_by_email?).to be true
              expect(new_person.previously_participated_in_caucus_or_primary?).to be true

              expect(modified_person.address).to eq modified_address
              expect(new_person.address).to eq modified_address
              expect(modified_address.most_supportive_resident).to eq new_person
              expect(modified_address.best_canvass_response).to eq new_person.canvass_response
              expect(modified_address.last_canvass_response).to eq new_person.canvass_response
            end
          end
        end

        context "when address doesn't exist" do

          it "creates the visit, the address and the people", vcr: { cassette_name: "requests/api/visits/create_visit/creates_the_visit_the_addres_and_the_people" }  do
            authenticated_post "visits", {
              data: {
                attributes: { duration_sec: 200 }
              },
              included: [
                {
                  type: "addresses",
                  attributes: {
                    latitude: 40.771913,
                    longitude: -73.9673735,
                    street_1: "5th Avenue",
                    city: "New York",
                    state_code: "NY"
                  }
                },
                {
                  type: "people",
                  attributes: {
                    first_name: "John",
                    last_name: "Doe",
                    canvass_response: "leaning_for",
                    party_affiliation: "democrat_affiliation",
                    email: "john@doe.com",
                    phone: "555-555-1212",
                    preferred_contact_method: "phone",
                    previously_participated_in_caucus_or_primary: true
                  }
                }
              ]
            }, token

            expect(last_response.status).to eq 200

            expect(Person.count).to eq 1
            expect(Address.count).to eq 1


            new_address = Address.last
            # basic fields
            expect(new_address.latitude).to eq 40.771913
            expect(new_address.longitude).to eq -73.9673735
            expect(new_address.street_1)
            expect(new_address.city).to eq "New York"
            expect(new_address.street_1).to eq "5th Avenue"
            expect(new_address.state_code).to eq "NY"
            # USPS verified fields
            expect(new_address.usps_verified_street_1).to eq "5 AVENUE A"
            expect(new_address.usps_verified_street_2).to eq ""
            expect(new_address.usps_verified_city).to eq "NEW YORK"
            expect(new_address.usps_verified_state).to eq "NY"
            expect(new_address.usps_verified_zip).to eq "10009-7944"

            new_person = Person.last
            expect(new_person.first_name).to eq "John"
            expect(new_person.last_name).to eq "Doe"
            expect(new_person.leaning_for?).to be true
            expect(new_person.democrat_affiliation?).to be true
            expect(new_person.email).to eq "john@doe.com"
            expect(new_person.phone).to eq "555-555-1212"
            expect(new_person.contact_by_phone?).to be true
            expect(new_person.previously_participated_in_caucus_or_primary?).to be true

            expect(new_person.address).to eq new_address
            expect(new_address.most_supportive_resident).to eq new_person
            expect(new_address.best_canvass_response).to eq new_person.canvass_response
          end
        end
      end

      context "when it fails creating the visit" do
        it "should return an error response" do
          address = create(:address, id: 1)

          authenticated_post "visits", {
            data: {
              attributes: { duration_sec: 200 },
            },
            included: [ { type: "addresses", id: 1, attributes: { } }, { type: "people", id: 10, attributes: {} } ]
          }, token
          expect(last_response.status).to eq 404
          expect(json).to be_a_valid_json_api_error.with_id "RECORD_NOT_FOUND"
        end
      end

      describe "setting 'address.best_canvass_response' directly" do
        before do
          @address = create(:address, id: 1)
        end

        def post_visit_with_address_best_canvass_response_set_to(best_canvass_response)
          authenticated_post "visits", {
            data: {
              attributes: { duration_sec: 200 },
            },
            included: [ { id: 1, type: "addresses", attributes: { best_canvass_response: best_canvass_response } } ]
          }, token
        end

        it "should be allowed for 'asked_to_leave'" do
          post_visit_with_address_best_canvass_response_set_to "asked_to_leave"
          expect(@address.reload.best_is_asked_to_leave?).to be true
        end

        it "should be allowed for 'not_home'" do
          post_visit_with_address_best_canvass_response_set_to "not_home"
          expect(@address.reload.best_is_not_home?).to be true
        end

        it "should be allowed for 'not_yet_visited" do
          post_visit_with_address_best_canvass_response_set_to "not_yet_visited"
          expect(@address.reload.best_is_not_yet_visited?).to be true
        end

        it "should not be allowed for 'unknown'" do
          post_visit_with_address_best_canvass_response_set_to "unknown"
          expect(@address.reload.best_is_unknown?).to be false
        end

        it "should not be allowed for 'strongly_for'" do
          post_visit_with_address_best_canvass_response_set_to "strongly_for"
          expect(@address.reload.best_is_strongly_for?).to be false
        end

        it "should not be allowed for 'leaning_for'" do
          post_visit_with_address_best_canvass_response_set_to "leaning_for"
          expect(@address.reload.best_is_leaning_for?).to be false
        end

        it "should not be allowed for 'undecided'" do
          post_visit_with_address_best_canvass_response_set_to "undecided"
          expect(@address.reload.best_is_undecided?).to be false
        end

        it "should not be allowed for 'leaning_against'" do
          post_visit_with_address_best_canvass_response_set_to "leaning_against"
          expect(@address.reload.best_is_leaning_against?).to be false
        end

        it "should not be allowed for 'strongly_against'" do
          post_visit_with_address_best_canvass_response_set_to "strongly_against"
          expect(@address.reload.best_is_strongly_against?).to be false
        end
      end

      describe "allowed address attributes" do
        it "allows setting 'address.last_canvass_response' directly" do
          address = create(:address, id: 1)
          authenticated_post "visits", {
            data: { attributes: { duration_sec: 200 }, },
            included: [ { id: 1, type: "addresses", attributes: { last_canvass_response: "not_yet_visited" } } ]
          }, token

          expect(Address.last.last_canvass_response).to eq "not_yet_visited"
        end
      end
    end
  end
end
