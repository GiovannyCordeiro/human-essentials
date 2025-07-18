Capybara.using_wait_time 10 do # allow up to 10 seconds for content to load in the test
  RSpec.describe "Partner management", type: :system, js: true do
    let(:organization) { create(:organization) }
    let(:user) { create(:user, organization: organization) }
    let(:organization_admin) { create(:organization_admin, organization: organization) }
    let(:partner) { create(:partner, organization: organization) }

    before do
      sign_in(user)
    end
    let!(:page_content_wait) { 10 } # allow up to 10 seconds for content to load in the test

    describe 'approving a partner that is awaiting approval' do
      let!(:partner_awaiting_approval) { create(:partner, :awaiting_review) }

      before do
        expect(partner_awaiting_approval.status).not_to eq(:approved)
      end

      context 'when the approval succeeds' do
        it 'should approve the partner' do
          visit partners_path

          assert page.has_content? partner_awaiting_approval.name
          click_on "Review Applicant's Profile"

          assert page.has_content?('Partner Profile')
          click_on 'Approve Partner'
          assert page.has_content? 'Partner approved!'

          expect(partner_awaiting_approval.reload.approved?).to eq(true)
        end
      end

      context 'when the approval does not succeed' do
        let(:fake_error_msg) { Faker::Games::ElderScrolls.dragon }
        before do
          allow_any_instance_of(PartnerApprovalService).to receive(:call)
          allow_any_instance_of(PartnerApprovalService).to receive_message_chain(:errors, :none?).and_return(false)
          allow_any_instance_of(PartnerApprovalService).to receive_message_chain(:errors, :full_messages).and_return(fake_error_msg)
        end

        it 'should show an error message and not approve the partner' do
          visit partners_path

          assert page.has_content? partner_awaiting_approval.name

          click_on "Review Applicant's Profile"
          click_on 'Approve Partner'
          assert page.has_content? "Failed to approve partner because: #{fake_error_msg}"

          expect(partner_awaiting_approval.reload.approved?).to eq(false)
        end
      end
    end

    describe 'adding a new partner and inviting them' do
      context 'when adding & inviting a partner successfully' do
        let(:partner_attributes) do
          {
            name: Faker::Name.name,
            email: Faker::Internet.email,
            quota: Faker::Number.within(range: 5..100),
            notes: Faker::Lorem.paragraph
          }
        end
        before do
          visit partners_path
          assert page.has_content? "Partner Agencies for #{organization.name}"

          click_on 'New Partner Agency'

          fill_in 'Name *', with: partner_attributes[:name]
          fill_in 'E-mail *', with: partner_attributes[:email]
          fill_in 'Quota', with: partner_attributes[:quota]
          fill_in 'Notes', with: partner_attributes[:notes]
          find('button', text: 'Add Partner Agency').click

          assert page.has_content? "Partner #{partner_attributes[:name]} added!"

          accept_confirm do
            find('tr', text: partner_attributes[:name]).find_link('Invite').click
          end

          assert page.has_content? "Partner #{partner_attributes[:name]} invited!"
        end

        it 'should have added the partner and invited them' do
          expect(Partner.find_by(email: partner_attributes[:email]).status).to eq('invited')
        end
      end

      context 'when adding a partner incorrectly' do
        let(:partner_attributes) do
          {
            name: Faker::Name.name
          }
        end
        before do
          visit partners_path
          assert page.has_content? "Partner Agencies for #{organization.name}"
          click_on 'New Partner Agency'

          fill_in 'Name *', with: partner_attributes[:name]

          find('button', text: 'Add Partner Agency').click
        end

        it 'should have not added a new partner and indicate the failure' do
          assert page.has_content? "Failed to add partner due to: "
          assert page.has_content? "New Partner for #{organization.name}"

          partner = Partner.find_by(name: partner_attributes[:name])
          expect(partner).to eq(nil)
        end
      end
    end

    describe "one step inviting a partner" do
      before do
        Partner.delete_all # ensure no pre created partner
      end

      let!(:uninvited_partner) { create(:partner, :uninvited) }

      context "when partner is uninvited and one step partner invite setting is on" do
        it "shows Invite and Approve button and approves the partner when clicked" do
          organization.update!(one_step_partner_invite: true)
          visit partners_path

          assert page.has_content? "Invite and Approve"
          expect do
            click_on "Invite and Approve"
          end.to change { uninvited_partner.reload.status }.from("uninvited").to("approved")
        end
      end

      context "when one step partner invite setting is off" do
        it "does not show invite and approve button" do
          organization.update!(one_step_partner_invite: false)

          visit partners_path

          expect(page).to_not have_content "Invite and Approve"
        end
      end
    end

    describe 'requesting recertification of a partner' do
      context 'GIVEN a user goes through the process of requesting recertification of partner' do
        let!(:partner_to_request_recertification) { create(:partner, status: 'approved') }

        before do
          sign_in(user)
          visit partners_path
        end

        it 'should notify the user that its been successful and change the partner status' do
          accept_confirm do
            find_button('Request Recertification').click
          end

          expect(page).to have_content "#{partner_to_request_recertification.name} recertification successfully requested!"
          expect(partner_to_request_recertification.reload.recertification_required?).to eq(true)
        end
      end
    end

    describe "#index" do
      before(:each) do
        @uninvited = create(:partner, name: "Bcd", status: :uninvited, organization: organization)
        @invited = create(:partner, name: "Abc", status: :invited, organization: organization)
        @approved = create(:partner, :approved, name: "Cde", status: :approved, organization: organization)
        @deactivated = create(:partner, name: "Def", status: :deactivated, organization: organization)
        visit partners_path
      end

      it "displays the partner agency names in alphabetical order" do
        expect(page).to have_css("table tr", count: 4, wait: page_content_wait)
        expect(page.find(:xpath, "//table/tbody/tr[1]/td[1]")).to have_content(@invited.name)
        expect(page.find(:xpath, "//table/tbody/tr[3]/td[1]")).to have_content(@approved.name)
        expect(page.find(:xpath, %(//*[@id="partner-status"]))).to have_content("3 Active")
        expect(page.find(:xpath, %(//*[@id="partner-status"]))).to have_content("1 Deactivated")
      end

      it "allows a user to invite a partner", js: true do
        partner = create(:partner, name: 'Charities', organization: organization)
        partner.primary_user.delete

        visit partners_path

        accept_alert("Send an invitation to #{partner.name} to begin using the partner application?") do
          ele = find('tr', text: partner.name)
          within(ele) { click_on "Invite" }
        end

        expect(page).to have_content "Partner #{partner.name} invited!", wait: page_content_wait
        expect(page.find(".alert")).to have_content "invited!", wait: page_content_wait
      end

      it "shows invite button only for unapproved partners" do
        expect(page.find('tr', text: 'Abc')).to have_content('Invited')
        expect(page.find('tr', text: 'Bcd')).to have_content('Invite')
        expect(page.find('tr', text: 'Cde')).to have_no_content('Invite')
      end

      context "when filtering" do
        it "allows the user to click on one of the statuses at the top to filter the results" do
          approved_count = Partner.approved.count
          within "table tbody" do
            expect(page).to have_css("tr", count: Partner.active.count)
          end
          within "#partner-status" do
            click_on "Approved"
          end
          within "table tbody" do
            expect(page).to have_css("tr", count: approved_count)
          end
        end
      end

      context "when exporting as CSV" do
        context "when filtering" do
          it "preserves the filter constraints in the CSV output" do
            approved_partners = Partner.approved.to_a
            within "#partner-status" do
              click_on "Approved"
            end

            page.find 'a.filtering', text: /Approved/

            click_on "Export Partner Agencies"
            wait_for_download
            expect(downloads.length).to eq(1)
            expect(download).to match(/.*\.csv/)

            rows = download_content.split("\n").slice(1..)
            expect(rows.size).to eq(approved_partners.size)
            expect(rows.first).to match(/#{approved_partners.first.email}/)
          end
        end
      end
    end

    describe "#show" do
      context "when viewing an uninvited partner" do
        let(:uninvited) { create(:partner, name: "Uninvited Partner", status: :uninvited) }
        subject { partner_path(uninvited.id) }

        it 'only has an edit option available' do
          visit subject

          expect(page).to have_selector(:link_or_button, 'Edit')
          expect(page).to_not have_selector(:link_or_button, 'View')
          expect(page).to_not have_selector(:link_or_button, 'Activate Partner Now')
          expect(page).to_not have_selector(:link_or_button, 'Add/Remind Partner')
        end
      end

      context "when viewing an invited partner as a partner" do
        let(:partner) { create(:partner, name: "Invited Partner", status: :invited) }
        before do
          sign_out(user)
          sign_in(partner.users.first)
        end
        it "redirects user to partners page root page (dashboard) with error message" do
          visit partner_path(partner.id)
          expect(page).to have_content("Dashboard - #{partner.name}")
          expect(page.find(".alert-danger")).to have_content("You must be logged in as the essentials bank's organization administrator to approve partner applications.")
        end
      end

      context "when viewing a deactivated partner" do
        let(:deactivated) { create(:partner, name: "Deactivated Partner", status: :deactivated) }
        subject { partner_path(deactivated.id) }
        it 'allows reactivation ' do
          visit subject
          expect(page).to have_selector(:link_or_button, 'Reactivate')
        end
      end

      context "when exporting as CSV" do
        subject { partner_path(partner.id) }

        let(:partner) do
          partner = create(:partner, :approved)
          partner.distributions << create(:distribution, :with_items, item_quantity: 1231)
          partner.distributions << create(:distribution, :with_items, item_quantity: 4564)
          partner.distributions << create(:distribution, :with_items, item_quantity: 7897)
          partner
        end

        let(:fake_get_return) do
          { "agency" => {
            "families_served" => Faker::Number.number,
            "children_served" => Faker::Number.number,
            "family_zipcodes" => Faker::Number.number,
            "family_zipcodes_list" => [Faker::Number.number]
          } }.to_json
        end

        context "when filtering" do
          it "preserves the filter constraints in the CSV output" do
            visit subject

            click_on "Export Partner Distributions"
            wait_for_download
            expect(downloads.length).to eq(1)
            expect(download).to match(/.*\.csv/)

            rows = download_content.split("\n").slice(1..)

            expect(rows.size).to eq(partner.distributions.size)
            expect(rows.join).to have_text('1231', count: 2)
            expect(rows.join).to have_text('4564', count: 2)
            expect(rows.join).to have_text('7897', count: 2)
          end
        end
      end
    end

    describe "#new" do
      subject { new_partner_path }

      it "User can add a new partner" do
        visit subject
        fill_in "Name", with: "Frank"
        fill_in "E-mail", with: "frank@frank.com"
        check 'send_reminders'
        click_button "Add Partner Agency"

        expect(page.find(".alert")).to have_content "added"
      end

      it "disallows a user from creating a new partner with empty name" do
        visit subject
        click_button "Add Partner Agency"

        expect(page.find(".alert")).to have_content "Failed to add partner due to:"
      end

      it "should not display inactive storage locations in dropdown" do
        create(:storage_location, name: "Inactive R Us", discarded_at: Time.zone.now)
        visit subject
        expect(page).to have_no_content "Inactive R Us"
      end
    end

    describe "#edit" do
      let!(:partner) { create(:partner, name: "Frank") }
      subject { edit_partner_path(partner.id) }

      it "User can update a partner" do
        visit subject
        name = Faker::Name.first_name
        fill_in "Name", with: name
        click_button "Update Partner"

        expect(page).to have_current_path(partner_path(partner.id))
        partner.reload
        expect(partner.name).to eq(name)
      end

      it "prevents a user from updating a partner with empty name" do
        visit subject
        fill_in "Name", with: ""
        click_button "Update Partner"

        expect(page.find(".alert")).to have_content "Something didn't work quite right -- try again?"
      end

      it "User can uncheck send_reminders" do
        visit subject
        uncheck 'send_reminders'
        click_button "Update Partner"

        expect(page.find(".alert")).to have_content "updated"
        partner.reload
        expect(partner.send_reminders).to be false
      end

      it "allows documents to be uploaded" do
        document_1 = Rails.root.join("spec/fixtures/files/distribution_program_address.pdf")
        document_2 = Rails.root.join("spec/fixtures/files/distribution_same_address.pdf")
        documents = [document_1, document_2]

        # Upload the documents
        visit subject
        attach_file(documents, make_visible: true) do
          page.find('input#partner_documents').click
        end

        # Save Progress
        click_button "Update Partner"

        # Expect documents to exist on show partner page
        expect(page).to have_current_path(partner_path(partner.id))
        expect(page).to have_link("distribution_program_address.pdf")
        expect(page).to have_link("distribution_same_address.pdf")

        # Expect documents to exist on edit partner page
        visit subject
        expect(page).to have_link("distribution_program_address.pdf")
        expect(page).to have_link("distribution_same_address.pdf")
      end
    end

    describe "#edit_profile" do
      let!(:partner) { create(:partner, name: "Frank") }
      subject { edit_profile_path(partner.id) }

      context "when step-wise editing is enabled" do
        before do
          Flipper.enable(:partner_step_form)
          visit subject
        end

        it "displays all sections in a closed state by default" do
          within ".accordion" do
            expect(page).to have_css("#agency_information.accordion-collapse.collapse", visible: false)
            expect(page).to have_css("#program_delivery_address.accordion-collapse.collapse", visible: false)

            partner.partials_to_show.each do |partial|
              expect(page).to have_css("##{partial}.accordion-collapse.collapse", visible: false)
            end
          end
        end

        it "allows sections to be opened, closed, filled in any order, and reviewed" do
          # Media
          find("button[data-bs-target='#media_information']").click
          expect(page).to have_css("#media_information.accordion-collapse.collapse.show", visible: true)
          within "#media_information" do
            fill_in "Website", with: "https://www.example.com"
          end
          find("button[data-bs-target='#media_information']").click
          expect(page).to have_css("#media_information.accordion-collapse.collapse", visible: false)

          # Executive director
          find("button[data-bs-target='#executive_director']").click
          expect(page).to have_css("#executive_director.accordion-collapse.collapse.show", visible: true)
          within "#executive_director" do
            fill_in "Executive Director Name", with: "Lisa Smith"
          end

          # Save Progress
          all("input[type='submit'][value='Save Progress']").last.click
          expect(page).to have_css(".alert-success", text: "Details were successfully updated.")

          # Save and Review
          all("input[type='submit'][value='Save and Review']").last.click
          expect(current_path).to eq(partner_path(partner.id))
          expect(page).to have_css(".alert-success", text: "Details were successfully updated.")
        end

        it "displays the edit view with sections containing validation errors expanded" do
          # Open up Media section and clear out website value
          find("button[data-bs-target='#media_information']").click
          within "#media_information" do
            fill_in "Website", with: ""
            uncheck "No Social Media Presence"
          end

          # Open Pick up person section and fill in 4 email addresses
          find("button[data-bs-target='#pick_up_person']").click
          within "#pick_up_person" do
            fill_in "Pick Up Person's Email", with: "email1@example.com, email2@example.com, email3@example.com, email4@example.com"
          end

          # Open Partner Settings section and uncheck all options
          find("button[data-bs-target='#partner_settings']").click
          within "#partner_settings" do
            uncheck "Enable Quantity-based Requests" if has_checked_field?("Enable Quantity-based Requests")
            uncheck "Enable Child-based Requests (unclick if you only do bulk requests)" if has_checked_field?("Enable Child-based Requests (unclick if you only do bulk requests)")
            uncheck "Enable Requests for Individuals" if has_checked_field?("Enable Requests for Individuals")
          end

          # Save Progress
          all("input[type='submit'][value='Save Progress']").last.click

          # Expect an alert-danger message containing validation errors
          expect(page).to have_css(".alert-danger", text: /There is a problem/)
          expect(page).to have_content("No social media presence must be checked if you have not provided any of Website, Twitter, Facebook, or Instagram.")
          expect(page).to have_content("Enable child based requests At least one request type must be set")
          expect(page).to have_content("Pick up email can't have more than three email addresses")

          # Expect media section, executive director section, and partner settings section to be opened
          expect(page).to have_css("#media_information.accordion-collapse.collapse.show", visible: true)
          expect(page).to have_css("#pick_up_person.accordion-collapse.collapse.show", visible: true)
          expect(page).to have_css("#partner_settings.accordion-collapse.collapse.show", visible: true)

          # Try to Submit and Review from error state
          all("input[type='submit'][value='Save and Review']").last.click

          # Expect an alert-danger message containing validation errors
          expect(page).to have_css(".alert-danger", text: /There is a problem/)
          expect(page).to have_content("No social media presence must be checked if you have not provided any of Website, Twitter, Facebook, or Instagram.")
          expect(page).to have_content("Enable child based requests At least one request type must be set")
          expect(page).to have_content("Pick up email can't have more than three email addresses")

          # Expect media section, executive director section, and partner settings section to be opened
          expect(page).to have_css("#media_information.accordion-collapse.collapse.show", visible: true)
          expect(page).to have_css("#pick_up_person.accordion-collapse.collapse.show", visible: true)
          expect(page).to have_css("#partner_settings.accordion-collapse.collapse.show", visible: true)
        end
      end
    end

    describe "#approve_partner" do
      let(:tooltip_message) do
        "Partner has not requested approval yet. Partners are able to request approval by going into 'My Organization' and clicking 'Request Approval' button."
      end
      let!(:invited_partner) { create(:partner, name: "Amelia Ebonheart", status: :invited) }
      let!(:awaiting_review_partner) { create(:partner, name: "Beau Brummel", status: :awaiting_review) }

      context "when partner has :invited status" do
        before { visit_approval_page(partner_name: invited_partner.name) }

        it { expect(page).to have_selector(:link_or_button, 'Approve Partner') }
      end

      context "when viewing a partner's users" do
        subject { partner_users_path(partner) }

        let(:partner) { create(:partner, name: "Partner") }
        let(:partner_user) { partner.users.first }
        let(:invitation_sent_at) { partner_user.invitation_sent_at.to_fs(:date_picker) }
        let(:last_sign_in_at) { partner_user.last_sign_in_at.to_fs(:date_picker) }

        before do
          sign_out(user)
          sign_in(organization_admin)
        end

        it 'can show users of a partner' do
          visit subject

          expect(page).to have_content(partner_user.name)
          expect(page).to have_content(partner_user.email)
        end
      end

      context "when partner has :awaiting_review status" do
        before { visit_approval_page(partner_name: awaiting_review_partner.name) }

        it { expect(page).to have_selector(:link_or_button, 'Approve Partner') }
      end
    end

    describe 'changing partner group association' do
      before do
        sign_in(user)
        visit partner_path(partner.id)
      end
      let!(:existing_partner_group) { create(:partner_group) }

      context 'when the partner has no partner group' do
        before do
          expect(partner.partner_group).to be_nil
        end

        it 'it should say they can request every item' do
          assert page.has_content? 'All Items Requestable'
          assert page.has_content? 'Settings'
        end
      end

      context 'when a partner is assigned to partner group' do
        before do
          assert page.has_content? 'All Items Requestable'
          partner.update!(partner_group: nil)
        end

        context 'that has requestable item categories' do
          let!(:item_category) do
            ic = create(:item_category, organization: organization)
            existing_partner_group.item_categories << ic
            ic
          end
          let!(:items_in_category) { create_list(:item, 3, item_category_id: item_category.id) }

          before do
            click_on 'Edit'
            select existing_partner_group.name
            click_on 'Update Partner'
          end

          it 'should properly indicate the requestable items and adjust the partners requestable items' do
            assert page.has_content? item_category.name
            expect { partner.reload }.to change(partner, :requestable_items).from([]).to(match_array(items_in_category))
          end
        end

        context 'that has no requestable item categories' do
          before do
            expect(existing_partner_group.item_categories).to be_empty
            click_on 'Edit'
            select existing_partner_group.name
            click_on 'Update Partner'
          end

          it 'should properly indicate the requestable items and adjust the partners requestable items' do
            assert page.has_content? 'No Items Requestable'
            expect { partner.reload }.to change(partner, :requestable_items).from([]).to([])
          end
        end
      end
    end

    describe "partner group management", type: :system, js: true do
      before do
        sign_in(user)
      end

      let!(:item_category_1) { create(:item_category, organization: organization) }
      let!(:item_category_2) { create(:item_category, organization: organization) }
      let!(:items_in_category_1) { create_list(:item, 3, item_category_id: item_category_1.id) }
      let!(:items_in_category_2) { create_list(:item, 3, item_category_id: item_category_2.id) }

      describe 'creating a new partner group' do
        it 'should allow creating a new partner group with item categories' do
          visit partners_path

          click_on 'Groups'
          click_on 'New Partner Group'
          fill_in 'Name *', with: 'Test Group'

          # Click on the second item category
          find("input#partner_group_item_category_ids_#{item_category_2.id}").click

          find_button('Add Partner Group').click

          assert page.has_content? 'Group Name', wait: page_content_wait
          assert page.has_content? 'Test Group'
          assert page.has_content? item_category_2.name
        end
      end

      describe 'editing a existing partner group' do
        let!(:existing_partner_group) { create(:partner_group, organization: organization) }
        before do
          existing_partner_group.item_categories << item_category_1
        end

        it 'should allow updating the partner name' do
          visit partners_path

          click_on 'Groups'
          assert page.has_content? existing_partner_group.name, wait: page_content_wait
          assert page.has_content? item_category_1.name

          click_on 'Edit'
          fill_in 'Name *', with: 'New Group Name'

          # Unset the existing category
          find("input#partner_group_item_category_ids_#{item_category_1.id}").click
          # Set a new one on the category
          find("input#partner_group_item_category_ids_#{item_category_2.id}").click

          find_button('Update Partner Group').click

          assert page.has_content? 'New Group Name', wait: page_content_wait
          refute page.has_content? item_category_1.name
          assert page.has_content? item_category_2.name
        end
      end
    end
  end
end

def visit_approval_page(partner_name:)
  visit partners_path
  ele = find('tr', text: partner_name)
  within(ele) { click_on "Review Applicant's Profile" }
end
