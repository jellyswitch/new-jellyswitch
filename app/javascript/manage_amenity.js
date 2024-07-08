document.addEventListener("turbo:load", function () {
  $('input[name="amenity-type"]').on('change', function () {
    const selectedType = $('input[name="amenity-type"]:checked').val();

    $('#amenities .nested-fields').each(function () {
      var $regularPrice = $(this).find('.regular-price');
      var $membershipPrice = $(this).find('.membership-price');

      if (selectedType === 'regular') {
        $regularPrice.show();
        $membershipPrice.hide();
      } else {
        $regularPrice.hide();
        $membershipPrice.show();
      }
    });
  }
  )
})