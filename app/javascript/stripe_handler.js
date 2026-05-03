function doStripe() {
  if (!document.getElementById('card-element')) {
    return;
  }
  window.stripe = Stripe(window.stripe_key);
  var elements = stripe.elements();

  var style = {};

  var card = elements.create('card', {style: style});
  card.mount('#card-element');

  card.addEventListener('change', function(event) {
    var displayError = document.getElementById('card-errors');
    if (event.error) {
      displayError.textContent = event.error.message;
    } else {
      displayError.textContent = '';
    }
  });

  window.has_token = false;
  var $stripeForm = document.getElementById('stripe-form');

  $stripeForm.addEventListener('submit', function(event) {
    var payByCheck = document.getElementById('out_of_band');

    if (payByCheck && payByCheck.checked) {
      return;
    }

    var submitButton = document.getElementById('stripe-submit');

    // Disable IMMEDIATELY (before async tokenize) so a quick double-tap on
    // mobile can't fire two submits with the same Stripe token. Re-enable
    // only on the tokenize-error path so the user can retry.
    if (submitButton) {
      if (submitButton.dataset.locked === 'true') {
        event.preventDefault();
        return;
      }
      submitButton.dataset.locked = 'true';
      submitButton.disabled = true;
    }

    if (window.has_token === false) {
      event.preventDefault();

      window.stripe.createToken(card).then(function(result) {
        if (result.error) {
          var errorElement = document.getElementById('card-errors');
          errorElement.textContent = result.error.message;
          if (submitButton) {
            submitButton.disabled = false;
            submitButton.dataset.locked = 'false';
          }
        } else {
          stripeTokenHandler(result.token);
        }
      });
    }
  });

  function stripeTokenHandler(token) {
    var form = document.getElementById('stripe-form');
    var hiddenInput = document.createElement('input');
    hiddenInput.setAttribute('type', 'hidden');
    hiddenInput.setAttribute('name', 'stripeToken');
    hiddenInput.setAttribute('value', token.id);
    form.appendChild(hiddenInput);
    window.has_token = true;
    console.log("setting has_token=true")
    console.log(window.has_token);

    form.requestSubmit();
  };
};

document.addEventListener('turbo:load', doStripe);
