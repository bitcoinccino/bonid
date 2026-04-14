# frozen_string_literal: true

require "rails_helper"

RSpec.describe PartnerPortal::TeamController, type: :controller do
  include Devise::Test::ControllerHelpers

  # ============================================================
  # SETUP
  # ============================================================
  let(:partner) { create(:partner, :verified, sector: "dgi") }

  let(:admin_user) do
    user = create(:user, email: "admin-#{SecureRandom.hex(4)}@bonid.ht")
    user.add_role(:partner_admin)
    user.update!(partner: partner)
    user
  end

  let(:supervisor_user) do
    user = create(:user, email: "supervisor-#{SecureRandom.hex(4)}@bonid.ht")
    user.add_role(:partner_supervisor)
    user.update!(partner: partner)
    user
  end

  let(:agent_user) do
    user = create(:user, email: "agent-#{SecureRandom.hex(4)}@bonid.ht")
    user.add_role(:partner_agent)
    user.update!(partner: partner)
    user
  end

  def sign_in_as(user)
    allow(controller).to receive(:authenticate_partner_admin!).and_return(true)
    allow(controller).to receive(:partner_admin_signed_in?).and_return(true)
    allow(controller).to receive(:current_partner_admin).and_return(user)
    allow(controller).to receive(:ensure_profile_complete!).and_return(true)

    # current_user is used throughout the controller — define it if missing
    unless controller.respond_to?(:current_user)
      controller.define_singleton_method(:current_user) { user }
    else
      allow(controller).to receive(:current_user).and_return(user)
    end

    controller.instance_variable_set(:@current_portal_user, user)
    controller.instance_variable_set(:@current_partner, partner)
  end

  before do
    sign_in_as(admin_user)

    # Prevent mailer calls
    allow(TeamMailer).to receive_message_chain(:invitation, :deliver_later)
    allow(TeamMailer).to receive_message_chain(:revoked, :deliver_later)
    allow(TeamMailer).to receive_message_chain(:suspended, :deliver_later)
    allow(TeamMailer).to receive_message_chain(:reactivated, :deliver_later)
  end

  # ============================================================
  # INDEX
  # ============================================================
  describe "GET #index" do
    it "lists team members" do
      get :index
      expect(response).to have_http_status(:ok)
      expect(controller.instance_variable_get(:@admins)).to include(admin_user)
    end

    context "with DGI sector (default grouping)" do
      it "groups agents and supervisors" do
        get :index
        expect(controller.instance_variable_get(:@agents)).to be_an(Array)
        expect(controller.instance_variable_get(:@supervisors)).to be_an(Array)
      end
    end

    context "with ONACA sector" do
      before { partner.update!(sector: "onaca") }

      it "groups surveyors, notaries, and supervisors" do
        get :index
        expect(controller.instance_variable_get(:@surveyors)).to be_an(Array)
        expect(controller.instance_variable_get(:@notaries)).to be_an(Array)
        expect(controller.instance_variable_get(:@supervisors)).to be_an(Array)
        expect(controller.instance_variable_get(:@agents)).to eq([])
      end
    end

    context "with banking sector" do
      before { partner.update!(sector: "commercial_bank") }

      it "groups bank_agents, bank_tellers, and bank_supervisors" do
        get :index
        expect(controller.instance_variable_get(:@bank_agents)).to be_an(Array)
        expect(controller.instance_variable_get(:@bank_tellers)).to be_an(Array)
        expect(controller.instance_variable_get(:@bank_supervisors)).to be_an(Array)
        expect(controller.instance_variable_get(:@agents)).to eq([])
      end
    end
  end

  # ============================================================
  # AUTHORIZATION — INVITE (admin only)
  # ============================================================
  describe "GET #new" do
    it "allows admin to access invite form" do
      get :new
      expect(response).to have_http_status(:ok)
    end

    it "blocks agents from invite form" do
      sign_in_as(agent_user)
      get :new
      expect(response).to redirect_to(partner_portal_team_index_path)
      expect(flash[:error]).to include("administratè")
    end

    it "blocks supervisors from invite form" do
      sign_in_as(supervisor_user)
      get :new
      expect(response).to redirect_to(partner_portal_team_index_path)
      expect(flash[:error]).to include("administratè")
    end
  end

  # ============================================================
  # SUSPEND
  # ============================================================
  describe "PATCH #suspend" do
    it "allows admin to suspend an agent" do
      patch :suspend, params: { id: agent_user.id, reason: "Envestigasyon" }
      expect(response).to redirect_to(partner_portal_team_index_path)
      expect(agent_user.reload.active?).to be false
      expect(flash[:success]).to include("sispann")
    end

    it "allows supervisor to suspend an agent" do
      sign_in_as(supervisor_user)
      patch :suspend, params: { id: agent_user.id }
      expect(agent_user.reload.active?).to be false
    end

    it "blocks supervisor from suspending an admin" do
      sign_in_as(supervisor_user)
      patch :suspend, params: { id: admin_user.id }
      expect(response).to redirect_to(partner_portal_team_index_path)
      expect(flash[:error]).to include("administratè")
      expect(admin_user.reload.active?).to be true
    end

    it "blocks agents from suspending anyone" do
      sign_in_as(agent_user)
      patch :suspend, params: { id: supervisor_user.id }
      expect(response).to redirect_to(partner_portal_team_index_path)
      expect(flash[:error]).to include("sipèvizè")
    end

    it "prevents self-suspension" do
      patch :suspend, params: { id: admin_user.id }
      expect(response).to redirect_to(partner_portal_team_index_path)
      expect(flash[:error]).to include("tèt ou")
      expect(admin_user.reload.active?).to be true
    end

    it "warns if already suspended" do
      agent_user.update!(active: false)
      patch :suspend, params: { id: agent_user.id }
      expect(flash[:warning]).to include("deja sispann")
    end

    it "creates an audit log" do
      expect {
        patch :suspend, params: { id: agent_user.id, reason: "Test" }
      }.to change(PartnerAuditLog, :count).by(1)

      log = PartnerAuditLog.last
      expect(log.event).to eq("team_member_suspended")
      expect(log.details).to include("Test")
    end
  end

  # ============================================================
  # REACTIVATE
  # ============================================================
  describe "PATCH #reactivate" do
    before { agent_user.update!(active: false) }

    it "allows admin to reactivate a suspended agent" do
      patch :reactivate, params: { id: agent_user.id }
      expect(response).to redirect_to(partner_portal_team_index_path)
      expect(agent_user.reload.active?).to be true
      expect(flash[:success]).to include("reaktive")
    end

    it "allows supervisor to reactivate a suspended agent" do
      sign_in_as(supervisor_user)
      patch :reactivate, params: { id: agent_user.id }
      expect(agent_user.reload.active?).to be true
    end

    it "blocks supervisor from reactivating an admin" do
      admin_copy = create(:user, email: "admin2-#{SecureRandom.hex(4)}@bonid.ht", active: false)
      admin_copy.add_role(:partner_admin)
      admin_copy.update!(partner: partner)

      sign_in_as(supervisor_user)
      patch :reactivate, params: { id: admin_copy.id }
      expect(flash[:error]).to include("administratè")
      expect(admin_copy.reload.active?).to be false
    end

    it "blocks agents from reactivating anyone" do
      sign_in_as(agent_user)
      patch :reactivate, params: { id: supervisor_user.id }
      expect(flash[:error]).to include("sipèvizè")
    end

    it "warns if already active" do
      agent_user.update!(active: true)
      patch :reactivate, params: { id: agent_user.id }
      expect(flash[:warning]).to include("deja aktif")
    end

    it "creates an audit log" do
      expect {
        patch :reactivate, params: { id: agent_user.id }
      }.to change(PartnerAuditLog, :count).by(1)

      log = PartnerAuditLog.last
      expect(log.event).to eq("team_member_reactivated")
    end
  end

  # ============================================================
  # UPDATE ROLE (admin only)
  # ============================================================
  describe "PATCH #update_role" do
    it "allows admin to change an agent to supervisor" do
      patch :update_role, params: { id: agent_user.id, role: "partner_supervisor" }
      expect(response).to redirect_to(partner_portal_team_index_path)
      expect(agent_user.reload.has_role?(:partner_supervisor)).to be true
      expect(agent_user.has_role?(:partner_agent)).to be false
      expect(flash[:success]).to include("Sipèvizè")
    end

    it "rejects invalid role for sector" do
      patch :update_role, params: { id: agent_user.id, role: "bank_teller" }
      expect(flash[:error]).to include("pa valid")
    end

    it "prevents self-role-change" do
      patch :update_role, params: { id: admin_user.id, role: "partner_agent" }
      expect(flash[:error]).to include("tèt ou")
    end

    it "blocks non-admins" do
      sign_in_as(supervisor_user)
      patch :update_role, params: { id: agent_user.id, role: "partner_admin" }
      expect(flash[:error]).to include("administratè")
    end

    it "creates an audit log" do
      expect {
        patch :update_role, params: { id: agent_user.id, role: "partner_supervisor" }
      }.to change(PartnerAuditLog, :count).by(1)

      log = PartnerAuditLog.last
      expect(log.event).to eq("team_member_role_changed")
      expect(log.details).to include("partner_supervisor")
    end

    context "with banking sector" do
      before { partner.update!(sector: "commercial_bank") }

      let(:bank_teller_user) do
        user = create(:user, email: "teller-#{SecureRandom.hex(4)}@bonid.ht")
        user.add_role(:bank_teller)
        user.update!(partner: partner)
        user
      end

      it "allows changing teller to bank_agent" do
        patch :update_role, params: { id: bank_teller_user.id, role: "bank_agent" }
        expect(bank_teller_user.reload.has_role?(:bank_agent)).to be true
        expect(bank_teller_user.has_role?(:bank_teller)).to be false
      end

      it "allows changing teller to bank_supervisor" do
        patch :update_role, params: { id: bank_teller_user.id, role: "bank_supervisor" }
        expect(bank_teller_user.reload.has_role?(:bank_supervisor)).to be true
      end
    end

    context "with ONACA sector" do
      before { partner.update!(sector: "onaca") }

      let(:surveyor_user) do
        user = create(:user, email: "surveyor-#{SecureRandom.hex(4)}@bonid.ht")
        user.add_role(:partner_agent_surveyor)
        user.update!(partner: partner)
        user
      end

      it "allows changing surveyor to notary" do
        patch :update_role, params: { id: surveyor_user.id, role: "partner_agent_notary" }
        expect(surveyor_user.reload.has_role?(:partner_agent_notary)).to be true
        expect(surveyor_user.has_role?(:partner_agent_surveyor)).to be false
      end
    end
  end

  # ============================================================
  # DESTROY (admin only)
  # ============================================================
  describe "DELETE #destroy" do
    it "allows admin to revoke an agent" do
      delete :destroy, params: { id: agent_user.id }
      expect(response).to redirect_to(partner_portal_team_index_path)
      expect(agent_user.reload.partner_id).to be_nil
      expect(agent_user.has_role?(:partner_agent)).to be false
      expect(flash[:success]).to include("retire")
    end

    it "prevents self-removal" do
      delete :destroy, params: { id: admin_user.id }
      expect(flash[:error]).to include("tèt ou")
      expect(admin_user.reload.partner_id).to eq(partner.id)
    end

    it "blocks non-admins" do
      sign_in_as(agent_user)
      delete :destroy, params: { id: supervisor_user.id }
      expect(flash[:error]).to include("administratè")
    end

    it "removes all partner roles on revoke" do
      agent_user.add_role(:partner_supervisor) # dual role
      delete :destroy, params: { id: agent_user.id }
      expect(agent_user.reload.has_role?(:partner_agent)).to be false
      expect(agent_user.has_role?(:partner_supervisor)).to be false
    end

    it "creates an audit log" do
      expect {
        delete :destroy, params: { id: agent_user.id }
      }.to change(PartnerAuditLog, :count).by(1)
    end

    context "with banking sector" do
      before { partner.update!(sector: "banking") }

      let(:teller) do
        user = create(:user, email: "teller-del-#{SecureRandom.hex(4)}@bonid.ht")
        user.add_role(:bank_teller)
        user.update!(partner: partner)
        user
      end

      it "removes banking roles on revoke" do
        delete :destroy, params: { id: teller.id }
        expect(teller.reload.has_role?(:bank_teller)).to be false
        expect(teller.partner_id).to be_nil
      end
    end
  end
end
