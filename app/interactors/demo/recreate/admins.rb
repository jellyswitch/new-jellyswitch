class Demo::Recreate::Admins
  include Interactor
  include ErrorsHelper

  delegate :operator, to: :context

  def call
    slugs.each do |slug|

      user = User.friendly.find(slug)
      user.update(admin: true)
    end
  end

  private

  def slugs
    [
      "alix-conyer",
      "brent-stellar"
    ]
  end
end