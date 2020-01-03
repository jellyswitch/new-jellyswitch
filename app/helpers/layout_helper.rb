module LayoutHelper
  def card
    render "layouts/card" do
      yield
    end
  end

  def super_wide_card
    render "layouts/super_wide_card" do
      yield
    end
  end

  def card_wrapper
    render "layouts/card_wrapper" do
      yield
    end
  end

  def wide_card
    render "layouts/wide_card" do
      yield
    end
  end

  def list_wrapper
    render "layouts/list_wrapper" do
      yield
    end
  end

  def list_item
    render(ListItem) do
      yield
    end
  end

  def breadcrumb
    render "layouts/breadcrumb" do
      yield
    end
  end

  def title(page_title)
    content_for(:title) { page_title }
    page_title
  end
end