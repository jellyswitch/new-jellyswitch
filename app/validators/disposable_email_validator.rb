# Rejects sign-ups from known disposable / throwaway email providers — the bulk
# of spam sign-ups. Front-door defense: stop the bot before a User row exists,
# instead of leaning on the post-signup confirmation/approval gates (which also
# punish real users). Applied on :create only and skipped for admin-created
# members (see User). Matches the exact domain or any subdomain of it.
#
# Curated list of the most common offenders — deliberately conservative to keep
# false positives near zero. Extend as new throwaway services show up in the
# unapproved queue.
class DisposableEmailValidator < ActiveModel::EachValidator
  DISPOSABLE_DOMAINS = %w[
    mailinator.com mailinator2.com notmailinator.com mailin8r.com
    guerrillamail.com guerrillamail.net guerrillamail.org guerrillamailblock.com grr.la sharklasers.com pokemail.net spam4.me
    10minutemail.com 10minutemail.net 20minutemail.com tempmail.com temp-mail.org tempmailaddress.com tempmail.net tempinbox.com tempr.email tempe-mail.com tempymail.com
    throwawaymail.com throwawaymailbox.com getairmail.com getnada.com nada.email dispostable.com mailnesia.com maildrop.cc mailcatch.com
    yopmail.com yopmail.net yopmail.fr trashmail.com trashmail.net trashymail.com mytrashmail.com mailmetrash.com
    fakeinbox.com fakemailgenerator.com fakemail.net spambox.us spam.la spamgourmet.com spamavert.com spamfree24.org spamhole.com
    emailondeck.com mohmal.com discard.email discardmail.com mintemail.com mailexpire.com meltmail.com mailtemp.info
    33mail.com anonbox.net deadaddress.com devnullmail.com dontreg.com gishpuppy.com incognitomail.org jetable.org
    klzlk.com kasmail.com killmail.com mailnull.com no-spam.ws nobulk.com oneoffmail.com rcpt.at recursor.net regbypass.com
    rmqkr.net sneakemail.com snkmail.com spambog.com spaml.com tempalias.com thisisnotmyrealemail.com tradermail.info
    willselfdestruct.com wuzup.net zoemail.net mailme.lv binkmail.com bobmail.info chammy.info maileater.com tmail.ws
    tempemail.net tempemail.com mailforspam.com tmailor.com mail-temporaire.fr cool.fr.nf nomail.xl.cx
  ].to_set.freeze

  def validate_each(record, attribute, value)
    return if value.blank?

    domain = value.to_s.downcase.strip.split("@").last
    return if domain.blank?

    blocked = DISPOSABLE_DOMAINS.include?(domain) ||
              DISPOSABLE_DOMAINS.any? { |d| domain.end_with?(".#{d}") }

    if blocked
      record.errors.add(
        attribute,
        options[:message] || "is from a temporary email provider. Please use a permanent email address.",
      )
    end
  end
end
