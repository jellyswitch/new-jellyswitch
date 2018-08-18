class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      scope.all
    end
  end

  protected

  def admin?
    user.admin?
  end

  def is_user?
    user.present?
  end

  def admin_or_member?
    admin? || member?
  end

  def owner_or_admin?
    owner? || admin?
  end

  def owner?
    user == record.user
  end

  def approved?
    user.approved?
  end

  def member?
    user.member?
  end
end
