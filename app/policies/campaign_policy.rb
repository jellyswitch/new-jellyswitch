# Campaigns are staff-only. The controller previously gated on nothing but
# `require_authentication`, so any authenticated member could create/send
# marketing campaigns for their operator — this closes that hole (mirrors the
# cross-surface guard audit). Every action requires an admin or manager.
class CampaignPolicy < ApplicationPolicy
  %i[
    index? show? new? create? update? destroy?
    send_campaign? pause? resume? clone? preview? test_send? exclude_recipient?
  ].each do |action|
    define_method(action) { admin_or_manager? }
  end
end
