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

  def is_user?
    user.present?
  end

  def admin?
    is_user? && user.admin?
  end

  def superadmin?
    is_user? && user.superadmin?
  end

  def member?
    is_user? && user.member?
  end

  def approved?
    is_user? && user.approved?
  end
  
  def owner?
    is_user? && (user == record.user)
  end
  
  def admin_or_member?
    raise "Use individual permission predicates instead"
  end

  def owner_or_admin?
    raise "Use individual permission predicates instead"
  end
end
