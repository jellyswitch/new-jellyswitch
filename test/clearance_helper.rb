module ClearanceHelper
  def log_in(user)
    user.update(password: 'password')
    ActsAsTenant.default_tenant = user.operator
    post login_path( params: { session: { email: user.email, password: 'password' } } )
  end
end