# Default welcome-drip + onboarding/follow-up email bodies.
#
# Brand-stripped from Cowork Tahoe's production templates (2026-05-15 export).
# Operator-specific details (addresses, room names, pricing, signatures, PDF
# attachments, multi-location refs) have been removed or replaced with merge
# tags. Operators see these defaults on first visit to /operator/product_email_templates
# and are expected to customize.
#
# Editing rules when adding to this file:
# - Use merge tags (see ProductEmailTemplate#available_merge_tags) instead of
#   hardcoding operator-specific content.
# - Keep the friendly, conversational tone — Cowork Tahoe wrote these as a
#   small family business and the warmth converts well; preserving that
#   voice as the default beats a "Hello valued customer" boilerplate.
# - HTML must be safe for ActionText (no <script>, no inline styles unless
#   needed for renderable widgets).
module WelcomeDripSeed
  BODIES = {
    %w[day_pass onboarding] => <<~HTML.strip,
      <div>Hi {{first_name}},&nbsp;<br><br>Thank you for booking a {{day_pass_type}} with {{space_name}} for {{date}}!</div>
      <div><br></div>
      <div>Here's the info you need to make the most of your visit:</div>
      <div><br></div>
      <div>Please download our mobile app to manage your day pass, building access, wifi, and more:<br><br>{{app_store_badge}}<br>{{play_store_badge}}</div>
      <div><br></div>
      <ul>
        <li><strong>Address:</strong> {{location_address}}</li>
        <li>The doors to the building <strong>are kept locked at all times</strong>. While your day pass is active, you can unlock them via the app: <em>"Building Access" &gt; "Open Lobby Door"</em>. Listen for the click, then open the door.</li>
        <li>Wifi info is in the app: <em>"Coworking Tools" &gt; "Internet Access"</em>.</li>
        <li>If you need a private space for calls, reservations can be made through the app.</li>
        <li>Help yourself to coffee, tea, &amp; snacks in the kitchen.</li>
      </ul>
      <div><br>Let us know if you have any questions.</div>
      <div><br></div>
      <div>The {{space_name}} team</div>
      <div><br></div>
      <div><em>Note: day-pass purchases are non-refundable, but if your plans change, contact us as soon as possible and we'll reschedule.</em></div>
    HTML

    %w[membership onboarding] => <<~HTML.strip,
      <div>Hi {{first_name}},&nbsp;</div>
      <div><br></div>
      <div>Thank you for signing up for a membership at {{space_name}}! We're excited to have you join our coworking community.</div>
      <div><br></div>
      <div>For new members, we like to schedule a quick onboarding tour to show you around and answer questions — typically about 15 minutes. Reply to this email with a time that works for you.</div>
      <div><br></div>
      <div>To get started, please download our mobile app — building access, wifi info, and reservations are all managed there:</div>
      <div>{{app_store_badge}}<br>{{play_store_badge}}</div>
      <div><br></div>
      <ul>
        <li><strong>Address:</strong> {{location_address}}</li>
        <li>The doors to the building <strong>are kept locked at all times</strong>. With your membership active, you can unlock them via the app: <em>"Building Access" &gt; "Open Lobby Door"</em>.</li>
        <li>Wifi info is in the app: <em>"Coworking Tools" &gt; "Internet Access"</em>.</li>
        <li>Help yourself to coffee, tea, &amp; snacks in the kitchen.</li>
      </ul>
      <div><br>If you have questions, just hit reply.</div>
      <div><br></div>
      <div>Welcome aboard,<br>The {{space_name}} team</div>
    HTML

    %w[reservation onboarding] => <<~HTML.strip,
      <div>Hi {{first_name}},&nbsp;</div>
      <div><br></div>
      <div>Thank you for booking with {{space_name}}. We have you confirmed in the {{room_name}} at {{time}} for {{duration}} on {{date}}.</div>
      <div><br></div>
      <div>Building access and wifi info are managed through our mobile app and will be active the day of your reservation:</div>
      <div>{{app_store_badge}}<br>{{play_store_badge}}</div>
      <div><br></div>
      <ul>
        <li><strong>Address:</strong> {{location_address}}</li>
        <li>The doors to the building <strong>are kept locked at all times</strong>. During your reservation you can unlock them via the app.</li>
        <li>Wifi info is on the app, and also posted in the room.</li>
        <li>Restrooms are accessible from the main hallway.</li>
        <li>Help yourself to coffee and tea in the kitchen.</li>
      </ul>
      <div><br>Reach out if you have any questions — and thanks again for booking with us.</div>
      <div><br></div>
      <div>The {{space_name}} team</div>
    HTML

    %w[office_lease onboarding] => <<~HTML.strip,
      <div>Hi {{first_name}},</div>
      <div><br></div>
      <div>Welcome to your new office at {{space_name}}!</div>
      <div><br></div>
      <div>We're excited to have you in the space. Reach out anytime if you need anything to make the office feel like home — additional furniture, signage, recommendations for vendors, etc.</div>
      <div><br></div>
      <div>The {{space_name}} team</div>
    HTML

    %w[day_pass follow_up] => <<~HTML.strip,
      <div>Hi {{first_name}},<br><br>Thanks for your visit — we appreciate your business.</div>
      <div><br></div>
      <div>If you enjoyed your day at {{space_name}}, we'd be grateful for a quick one-sentence Google review. Every review helps us serve more people.</div>
      <div><br></div>
      <div>{{google_review_button}}</div>
      <div><br></div>
      <div>If you have feedback for us instead, just reply to this email — we want to hear it.</div>
      <div><br></div>
      <div>Best,<br>The {{space_name}} team</div>
    HTML

    %w[membership follow_up] => <<~HTML.strip,
      <div>Hi {{first_name}},<br><br>Checking in to see how your {{plan_name}} membership is going.</div>
      <div><br></div>
      <div>If {{space_name}} is working out for you, we'd really appreciate a quick one-sentence Google review.</div>
      <div><br></div>
      <div>{{google_review_button}}</div>
      <div><br></div>
      <div>If something isn't working — or you have ideas for how to improve the space — just reply. We want to hear it.</div>
      <div><br></div>
      <div>Best,<br>The {{space_name}} team</div>
    HTML

    %w[reservation follow_up] => <<~HTML.strip,
      <div>Hi {{first_name}},<br><br>Hope your reservation at {{space_name}} went well!</div>
      <div><br></div>
      <div>If the room worked out for what you needed, a quick one-sentence Google review would mean a lot.</div>
      <div><br></div>
      <div>{{google_review_button}}</div>
      <div><br></div>
      <div>If anything was off, reply to this email and let us know.</div>
      <div><br></div>
      <div>Best,<br>The {{space_name}} team</div>
    HTML

    %w[office_lease follow_up] => <<~HTML.strip,
      <div>Hi {{first_name}},</div>
      <div><br></div>
      <div>It's been a while since you moved into your office at {{space_name}} — checking in to see how it's working out.</div>
      <div><br></div>
      <div>Anything you'd like to change, fix, or add? Just reply and let us know.</div>
      <div><br></div>
      <div>The {{space_name}} team</div>
    HTML

    %w[signup_nudge nudge] => <<~HTML.strip,
      <div>Hi {{first_name}},</div>
      <div><br></div>
      <div>Thanks for signing up at {{space_name}}! We noticed you haven't booked a day pass or membership yet.</div>
      <div><br></div>
      <div>If you'd like to come check us out, day passes are a great way to try the space before committing. Reply to this email with any questions.</div>
      <div><br></div>
      <div>The {{space_name}} team</div>
    HTML

    %w[day_pass re_engagement] => <<~HTML.strip,
      <div>Hi {{first_name}},</div>
      <div><br></div>
      <div>It's been {{days_since_last_visit}} days since your last day pass at {{space_name}}. We'd love to see you again.</div>
      <div><br></div>
      <div>If our space worked for you, a membership might be worth a look — more affordable per day and includes member-only perks. Reply to this email if you'd like more info, or just book another day pass when you're ready.</div>
      <div><br></div>
      <div>The {{space_name}} team</div>
    HTML

    %w[reservation re_engagement] => <<~HTML.strip,
      <div>Hi {{first_name}},</div>
      <div><br></div>
      <div>It's been {{days_since_last_visit}} days since your last reservation at {{space_name}}.</div>
      <div><br></div>
      <div>Need another room for a meeting, call, or focused work session? Reply or book through the app any time.</div>
      <div><br></div>
      <div>The {{space_name}} team</div>
    HTML

    %w[membership past_member_recovery] => <<~HTML.strip,
      <div>Hi {{first_name}},</div>
      <div><br></div>
      <div>Your membership at {{space_name}} ended on {{plan_canceled_on}} — we've missed having you in the space.</div>
      <div><br></div>
      <div>If life or work has shifted and you're ready to come back, we'd love to have you. Reply to this email and we can help you pick up where you left off, or try a day pass to ease back in.</div>
      <div><br></div>
      <div>The {{space_name}} team</div>
    HTML
  }.freeze

  def self.body_for(product_type, email_type)
    BODIES[[product_type.to_s, email_type.to_s]]
  end
end
