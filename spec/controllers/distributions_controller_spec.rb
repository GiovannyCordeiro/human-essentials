RSpec.describe DistributionsController, type: :controller do
  include ActiveJob::TestHelper

  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:partner) { create(:partner, organization: organization) }

  after(:each) do
    clear_enqueued_jobs
  end

  context "While signed in" do
    before do
      sign_in(user)
    end

    describe "POST #create" do
      let(:available_item) { create(:item, name: "Available Item", organization: organization, on_hand_minimum_quantity: 5) }
      let!(:first_storage_location) { create(:storage_location, :with_items, item: available_item, item_quantity: 20, organization: organization) }
      let!(:second_storage_location) { create(:storage_location, :with_items, item: available_item, item_quantity: 20, organization: organization) }
      context "when distribution causes inventory to remain above minimum quantity for an organization" do
        let(:params) do
          {
            distribution: {
              partner_id: partner.id,
              issued_at: Date.yesterday,
              storage_location_id: first_storage_location.id,
              line_items_attributes:
              {
                "0": { item_id: first_storage_location.items.first.id, quantity: 10 }
              }
            }
          }
        end

        subject { post :create, params: params.merge(format: :turbo_stream) }

        it "does not display an error" do
          subject

          expect(flash[:alert]).to be_nil
        end

        context "when distribution causes inventory to fall below minimum quantity for a storage location" do
          let(:params) do
            {
              distribution: {
                partner_id: partner.id,
                storage_location_id: second_storage_location.id,
                issued_at: Date.yesterday,
                line_items_attributes:
                  {
                    "0": { item_id: second_storage_location.items.first.id, quantity: 18 }
                  }
              }
            }
          end
          it "does not display an error" do
            subject
            expect(flash[:notice]).to eq("Distribution created!")
            expect(flash[:error]).to be_nil
          end
        end
      end

      context "when distribution causes inventory quantity to be below minimum quantity for an organization" do
        let(:first_item) { create(:item, name: "Item 1", organization: organization, on_hand_minimum_quantity: 5) }
        let(:storage_location) { create(:storage_location, :with_items, item: first_item, item_quantity: 20, organization: organization) }
        let(:params) do
          {
            distribution: {
              partner_id: partner.id,
              storage_location_id: storage_location.id,
              issued_at: Date.yesterday,
              line_items_attributes:
                {
                  "0": { item_id: storage_location.items.first.id, quantity: 18 }
                }
            }
          }
        end

        subject { post :create, params: params.merge(format: :turbo_stream) }

        it "redirects with a flash notice and a flash error" do
          expect(subject).to have_http_status(:redirect)
          expect(flash[:notice]).to eq("Distribution created!")
          expect(flash[:alert]).to eq("The following items have fallen below the minimum on hand quantity, bank-wide: Item 1")
        end

        context "when distribution causes inventory quantity to be below recommended quantity for an organization" do
          let(:second_item) { create(:item, name: "Item 2", organization: organization, on_hand_minimum_quantity: 5, on_hand_recommended_quantity: 10) }
          let(:storage_location) { create(:storage_location, organization: organization) }
          let(:params) do
            {
              distribution: {
                partner_id: partner.id,
                storage_location_id: storage_location.id,
                issued_at: Date.yesterday,
                line_items_attributes:
                  {
                    "0": { item_id: storage_location.items.first.id, quantity: 18 },
                    "1": { item_id: storage_location.items.second.id, quantity: 15 }
                  }
              }
            }
          end
          before do
            TestInventory.create_inventory(organization, {
              storage_location.id => {
                first_item.id => 20,
                second_item.id => 20
              }
            })
          end
          it "displays an error for both minimum and recommended quantity for an organization" do
            expect(subject).to have_http_status(:redirect)
            expect(flash[:notice]).to eq("Distribution created!")
            expect(flash[:alert]).to include("The following items have fallen below the recommended on hand quantity, bank-wide: Item 2")
            expect(flash[:alert]).to include("The following items have fallen below the minimum on hand quantity, bank-wide: Item 1")
          end
        end
      end

      context "multiple line_items that have inventory quantity below minimum quantity for an organization" do
        let(:item1) { create(:item, name: "Item 1", organization: organization, on_hand_minimum_quantity: 5, on_hand_recommended_quantity: 10) }
        let(:item2) { create(:item, name: "Item 2", organization: organization, on_hand_minimum_quantity: 5, on_hand_recommended_quantity: 10) }
        let(:storage_location) { create(:storage_location, organization: organization) }
        before(:each) do
          TestInventory.create_inventory(organization, {
            storage_location.id => {
              item1.id => 20,
              item2.id => 20
            }
          })
        end
        let(:params) do
          {
            distribution: {
              partner_id: partner.id,
              storage_location_id: storage_location.id,
              issued_at: Date.yesterday,
              line_items_attributes:
                {
                  "0": { item_id: item1.id, quantity: 18 },
                  "1": { item_id: item2.id, quantity: 18 }
                }
            }
          }
        end

        subject { post :create, params: params.merge(format: :turbo_stream) }

        it "redirects with a flash notice and a flash error" do
          expect(subject).to have_http_status(:redirect)
          expect(flash[:notice]).to eq("Distribution created!")
          expect(flash[:alert]).to include("The following items have fallen below the minimum on hand quantity, bank-wide")
          expect(flash[:alert]).to include("Item 1")
          expect(flash[:alert]).to include("Item 2")
        end
      end

      context "multiple line_items that have inventory quantity below recommended quantity for an organization" do
        let(:item1) { create(:item, name: "Item 1", organization: organization, on_hand_recommended_quantity: 5) }
        let(:item2) { create(:item, name: "Item 2", organization: organization, on_hand_recommended_quantity: 5) }
        let(:storage_location) { create(:storage_location, organization: organization) }
        before(:each) do
          TestInventory.create_inventory(organization, {
            storage_location.id => {
              item1.id => 20,
              item2.id => 20
            }
          })
        end
        let(:params) do
          {
            distribution: {
              partner_id: partner.id,
              storage_location_id: storage_location.id,
              issued_at: Date.yesterday,
              line_items_attributes:
                {
                  "0": { item_id: item1.id, quantity: 18 },
                  "1": { item_id: item2.id, quantity: 18 }
                }
            }
          }
        end

        subject { post :create, params: params.merge(format: :turbo_stream) }

        it "redirects with a flash notice and a flash alert" do
          expect(subject).to have_http_status(:redirect)
          expect(flash[:notice]).to eq("Distribution created!")
          expect(flash[:alert]).to eq("The following items have fallen below the recommended on hand quantity, bank-wide: Item 1, Item 2")
        end
      end

      context "when line item quantity is not positive" do
        let(:item) { create(:item, name: "Item 1", organization: organization, on_hand_minimum_quantity: 5) }
        let(:storage_location) { create(:storage_location, :with_items, item: item, item_quantity: 2, organization: organization) }
        let(:params) do
          {
            distribution: {
              partner_id: partner.id,
              storage_location_id: storage_location.id,
              issued_at: Date.yesterday,
              line_items_attributes:
                {
                  "0": { item_id: storage_location.items.first.id, quantity: 0 }
                }
            }
          }
        end
        subject { post :create, params: params.merge(format: :turbo_stream) }

        it "flashes an error" do
          expect(subject).to have_http_status(:bad_request)
          expect(flash[:error]).to include("Sorry, we weren't able to save the distribution. \n Validation failed: Inventory Item 1's quantity needs to be at least 1")
        end
      end

      context "when distribution reminder email is enabled" do
        let(:params) do
          {
            distribution: {
              partner_id: partner.id,
              issued_at: Date.tomorrow,
              storage_location_id: first_storage_location.id,
              line_items_attributes:
                {
                  "0": { item_id: first_storage_location.items.first.id, quantity: 10 }
                },
              reminder_email_enabled: true
            }
          }
        end
        subject { post :create, params: params.merge(format: :turbo_stream) }

        context "when partner has enabled send_reminders" do
          before(:each) do
            partner.send_reminders = true
          end
          it "should schedule the reminder email" do
            subject
            expect(enqueued_jobs[1]["arguments"][1]).to eq("reminder_email")
          end

          it "should not schedule a reminder for a date in the past" do
            params[:distribution][:issued_at] = Date.yesterday
            subject
            expect(enqueued_jobs.size).to eq(1)
          end
        end

        context "when partner has disabled send_reminders" do
          let(:partner) { create(:partner, organization: organization, send_reminders: false) }

          it "should not schedule an email reminder for a partner that disabled reminders" do
            subject
            expect(enqueued_jobs.size).to eq(0)
          end
        end
      end
    end

    describe "PUT #update" do
      context "when distribution causes inventory quantity to be below recommended quantity for an organization" do
        let(:item1) { create(:item, name: "Item 1", organization: organization, on_hand_recommended_quantity: 5) }
        let(:item2) { create(:item, name: "Item 2", organization: organization, on_hand_recommended_quantity: 5) }
        let(:storage_location) { create(:storage_location, organization: organization) }
        before(:each) do
          TestInventory.create_inventory(organization, {
            storage_location.id => {
              item1.id => 20,
              item2.id => 20
            }
          })
        end
        let(:distribution) { create(:distribution, storage_location: storage_location) }
        let(:params) do
          {
            id: distribution.id,
            distribution: {
              storage_location_id: distribution.storage_location.id,
              issued_at: Date.yesterday,
              line_items_attributes:
                {
                  "0": { item_id: item1.id, quantity: 18 },
                  "1": { item_id: item2.id, quantity: 18 }
                }
            }
          }
        end

        subject { put :update, params: params }

        it "redirects with a flash notice and a flash error" do
          expect(subject).to have_http_status(:redirect)
          expect(flash[:notice]).to eq("Distribution updated!")
          expect(flash[:alert]).to eq("The following items have fallen below the recommended on hand quantity, bank-wide: Item 1, Item 2")
        end
      end

      context "when distribution causes inventory quantity to be below minimum quantity for an organization" do
        let(:item1) { create(:item, name: "Item 1", organization: organization, on_hand_minimum_quantity: 5) }
        let(:item2) { create(:item, name: "Item 2", organization: organization, on_hand_minimum_quantity: 5) }
        let(:storage_location) { create(:storage_location) }
        before(:each) do
          TestInventory.create_inventory(organization, {
            storage_location.id => {
              item1.id => 20,
              item2.id => 20
            }
          })
        end
        let(:distribution) { create(:distribution, storage_location: storage_location, organization: organization) }
        let(:params) do
          {
            id: distribution.id,
            distribution: {
              storage_location_id: distribution.storage_location.id,
              line_items_attributes:
                {
                  "0": { item_id: item1.id, quantity: 18 },
                  "1": { item_id: item2.id, quantity: 18 }
                }
            }
          }
        end

        subject { put :update, params: params }

        it "redirects with a flash notice and a flash error" do
          expect(subject).to have_http_status(:redirect)
          expect(flash[:notice]).to eq("Distribution updated!")
          expect(flash[:alert]).to eq("The following items have fallen below the minimum on hand quantity, bank-wide: Item 1, Item 2")
        end
      end

      context "when distribution has items updated for minimum quantity" do
        let(:item1) { create(:item, name: "Item 1", organization: organization, on_hand_minimum_quantity: 5) }
        let(:item2) { create(:item, name: "Item 2", organization: organization, on_hand_minimum_quantity: 5) }
        let(:storage_location) { create(:storage_location, organization: organization) }
        before(:each) do
          TestInventory.create_inventory(organization, {
            storage_location.id => {
              item1.id => 20,
              item2.id => 20
            }
          })
        end
        let(:distribution) { create(:distribution, :with_items, item: item1, storage_location: storage_location, organization: organization) }
        let(:params) do
          {
            id: distribution.id,
            distribution: {
              storage_location_id: distribution.storage_location.id,
              issued_at: Date.yesterday,
              line_items_attributes:
                {
                  "0": { item_id: item1.id, quantity: 4 },
                  "1": { item_id: item2.id, quantity: 4 }
                }
            }
          }
        end

        before do
          ActiveJob::Base.queue_adapter = :test
        end

        it "redirects with a flash notice and send send_notification" do
          expected_distribution_changes = {
            removed: [],
            updates: [
              {
                name: item1.name,
                new_quantity: 4,
                old_quantity: 100
              }
            ]
          }

          expect(PartnerMailerJob).to receive(:perform_now).with(organization.id, distribution.id, "Your Distribution Has Changed", expected_distribution_changes)

          put :update, params: params

          expect(response).to have_http_status(:redirect)
          expect(flash[:notice]).to eq("Distribution updated!")
          expect(flash[:error]).to be_nil
          expect(flash[:alert]).to be_nil
        end
      end

      context "when distribution reminder email is enabled" do
        let(:item1) { create(:item, name: "Item 1", organization: organization, on_hand_minimum_quantity: 0) }
        let(:storage_location) { create(:storage_location, organization: organization) }
        let(:distribution) { create(:distribution, :with_items, item: item1, storage_location: storage_location, organization: organization, reminder_email_enabled: false, partner: partner) }
        let(:params) do
          {
            id: distribution.id,
            distribution: {
              storage_location_id: distribution.storage_location.id,
              issued_at: Date.tomorrow,
              line_items_attributes:
                {
                  "0": { item_id: item1.id, quantity: 1 }
                },
              reminder_email_enabled: true
            }
          }
        end
        subject { put :update, params: params }

        context "when partner has enabled send_reminders" do
          before(:each) do
            partner.send_reminders = true
          end
          it "should schedule the reminder email" do
            subject
            expect(enqueued_jobs.first["arguments"][1]).to eq("reminder_email")
          end

          it "should not schedule a reminder for a date in the past" do
            params[:distribution][:issued_at] = Date.yesterday
            subject
            expect(enqueued_jobs.size).to eq(0)
          end
        end

        context "when partner has disabled send_reminders" do
          let(:partner) { create(:partner, organization: organization, send_reminders: false) }

          it "should not schedule an email reminder for a partner that disabled reminders" do
            subject
            expect(enqueued_jobs.size).to eq(0)
          end
        end
      end
    end
  end
end
