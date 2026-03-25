# app/policies/incident_report_policy.rb
class IncidentReportPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      Rails.logger.info "Policy Scope resolver: user=#{user.inspect}, role=#{user&.role&.downcase}, approved?=#{user&.status_approved?}, status=#{user&.status}"
      # Rails.logger.info "Policy Scope resolver: user=#{user.inspect}, role=#{user&.role&.downcase}, approved=#{user&.approved}, status=#{user&.status}"
      if user&.admin? && user&.status_approved? && user&.active?
        scope.all
      elsif user&.officer? && user&.status_approved? && user&.active?
        scope.where(officer: user)
      else
        scope.none
      end
    end
  end

  def index?
    result = (user&.officer? || user&.admin?) && user&.status_approved? && user&.active? || false
    Rails.logger.info "Policy index?: user=#{user.inspect}, officer?=#{user&.officer?}, admin?=#{user&.admin?}, approved?=#{user&.status_approved?}, active?=#{user&.active?}, result=#{result}"
    result
  end

  def show?
    (user&.officer? && record.officer == user && user&.status_approved? && user&.active?) || (user&.admin? && user&.status_approved? && user&.active?) || false
  end

  def create?
    user&.officer? && user&.status_approved? && user&.active? || false
  end

  def new?
    create?
  end

  def update?
    (user&.officer? && record.officer == user && user&.status_approved? && user&.active?) || false
  end

  def edit?
    update?
  end
end
