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

    // has_token=true means stripeTokenHandler already ran and is calling
    // requestSubmit() to actually fire the POST — let it through unmolested.
    // Only the user-initiated initial submit needs the dedupe lock.
    if (window.has_token === true) {
      return;
    }

    var submitButton = document.getElementById('stripe-submit');

    // Initial user-initiated submit. If we're already mid-tokenize from a
    // previous tap, ignore this one entirely — that's the double-tap case.
    if (submitButton && submitButton.dataset.locked === 'true') {
      event.preventDefault();
      return;
    }

    if (submitButton) {
      submitButton.dataset.locked = 'true';
      submitButton.disabled = true;
    }

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
