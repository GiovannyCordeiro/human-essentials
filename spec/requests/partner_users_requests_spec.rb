# spec/requests/partner_users_controller_spec.rb

RSpec.describe PartnerUsersController, type: :request do
  let!(:partner) { create(:partner) } # Assuming you have a factory for creating partners
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:org_admin) { create(:organization_admin, organization: organization) }
  let(:default_params) do
    {organization_id: @organization.to_param}
  end

  describe "GET #index" do
    context "while signed in as org admin" do
      before do
        sign_in(org_admin)
      end

      it "renders the index template and assigns @users" do
        get partner_users_path(default_params.merge(partner_id: partner))
        expect(response).to render_template(:index)
        expect(assigns(:users)).to eq(partner.users)
      end
    end

    context "while signed in as org user" do
      before do
        sign_in(user)
      end

      it "denies access" do
        get partner_users_path(default_params.merge(partner_id: partner))

        expect(response).to redirect_to(dashboard_path)
        expect(flash[:error]).to match(/access denied/i)
      end
    end
  end

  describe "POST #create" do
    let(:valid_user_params) do
      {
        email: "meow@example.com",
        name: "Meow Mix"
      }
    end

    context "while signed in as org admin" do
      before do
        sign_in(org_admin)
      end

      context "with valid user params" do
        it "invites a new user and redirects back with notice" do
          expect {
            post partner_users_path(default_params.merge(partner_id: partner)), params: {user: valid_user_params}
          }.to change(User.all, :count).by(1)

          expect(response).to redirect_to(root_path)
          expect(flash[:notice]).to include("has been invited. Invitation email sent to")
        end
      end

      context "with invalid user params" do
        it "renders the index template with alert" do
          expect {
            post partner_users_path(default_params.merge(partner_id: partner)), params: {user: {email: "invalid_email"}}
          }.not_to change(User, :count)

          expect(response).to render_template(:index)
          expect(flash[:alert]).to eq("Invitation failed. Check the form for errors.")
        end
      end

      context "with existing user params" do
        it "renders the index template with error" do
          expect {
            post partner_users_path(default_params.merge(partner_id: partner)), params: {user: {email: partner.email}}
          }.not_to change(User, :count)

          expect(response).to redirect_to(partner_users_path)
          expect(flash[:error]).to eq("User already has the requested role!")
        end
      end
    end

    context "while signed in as org user" do
      before do
        sign_in(user)
      end

      it "denies access" do
        post partner_users_path(default_params.merge(partner_id: partner)), params: {user: valid_user_params}

        expect(response).to redirect_to(dashboard_path)
        expect(flash[:error]).to match(/access denied/i)
      end
    end
  end

  describe "DELETE #destroy" do
    let!(:partner_user) do
      UserInviteService.invite(
        email: "meow@example.com",
        name: "Meow Mix",
        roles: [Role::PARTNER],
        resource: partner
      )
    end

    context "while signed in as org admin" do
      before do
        sign_in(org_admin)
      end

      it "removes the user role from the partner and redirects back with notice" do
        expect {
          delete partner_user_path(default_params.merge(partner_id: partner, id: partner_user))
        }.to change { partner_user.roles.count }.from(1).to(0)

        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("Access to #{partner.name} has been revoked for #{partner_user.name}.")
      end

      it "redirects back with alert if the user role removal fails" do
        allow_any_instance_of(User).to receive(:remove_role).and_return(false)

        delete partner_user_path(default_params.merge(partner_id: partner, id: partner_user))

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Invitation failed. Check the form for errors.")
      end
    end

    context "while signed in as org user" do
      before do
        sign_in(user)
      end

      it "denies access" do
        delete partner_user_path(default_params.merge(partner_id: partner, id: partner_user))

        expect(response).to redirect_to(dashboard_path)
        expect(flash[:error]).to match(/access denied/i)
      end
    end
  end

  describe "PATCH #resend_invitation" do
    let!(:partner_user) do
      UserInviteService.invite(
        email: "meow@example.com",
        name: "Meow Mix",
        roles: [Role::PARTNER],
        resource: partner
      )
    end

    context "while signed in as org admin" do
      before do
        sign_in(org_admin)
      end

      context "when the user has not accepted the invitation" do
        it "resends the invitation and redirects back with notice" do
          expect_any_instance_of(User).to receive(:invite!)

          post resend_invitation_partner_user_path(default_params.merge(partner_id: partner, id: partner_user))

          expect(response).to redirect_to(root_path)
          expect(flash[:notice]).to eq("Invitation email sent to #{partner_user.email}")
        end
      end

      context "when the user has already accepted the invitation" do
        it "redirects back with alert" do
          partner_user.update!(invitation_accepted_at: Time.zone.now)

          post resend_invitation_partner_user_path(default_params.merge(partner_id: partner, id: partner_user))

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq("User has already accepted invitation.")
        end
      end
    end

    context "while signed in as org user" do
      before do
        sign_in(user)
      end

      it "denies access" do
        post resend_invitation_partner_user_path(default_params.merge(partner_id: partner, id: partner_user))

        expect(response).to redirect_to(dashboard_path)
        expect(flash[:error]).to match(/access denied/i)
      end
    end
  end

  describe "POST #reset_password" do
    let!(:partner_user) do
      UserInviteService.invite(
        email: "meow@example.com",
        name: "Meow Mix",
        roles: [Role::PARTNER],
        resource: partner
      )
    end

    context "while signed in as org admin" do
      before do
        sign_in(org_admin)
      end

      context "when a bank needs to reset a partner user's password" do
        it "resends the reset password email and redirects back to root_path" do
          expect {
            post reset_password_partner_user_path(default_params.merge(partner_id: partner, id: partner_user))
          }.to change { ActionMailer::Base.deliveries.count }.by(1)
          expect(response).to redirect_to(root_path)
          expect(flash[:notice]).to eq("Password e-mail sent!")
        end
      end
    end

    context "while signed in as org user" do
      before do
        sign_in(user)
      end

      it "denies access" do
        post reset_password_partner_user_path(default_params.merge(partner_id: partner, id: partner_user))

        expect(response).to redirect_to(dashboard_path)
        expect(flash[:error]).to match(/access denied/i)
      end
    end
  end
end
