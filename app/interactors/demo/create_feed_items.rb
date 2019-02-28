class Demo::CreateFeedItems
  include Interactor
  include FeedItemCreator

  def call
    operator = context.operator

    feed_item_samples.each do |text|
      user = operator.users.admins.non_superadmins.sample
      blob = {text: text, type: "post"}
      day = Time.current - rand(15).days

      create_feed_item(operator, user, blob, day: day)
    end
  end

  def feed_item_samples
    ["Wrote and sent out email blast",
      "Security issue - some guy walked in behind a member, had to intercept and ask him to leave. ",
      "Help team meeting today",
      "Spoke to Brad about talking too loudly on the phone in the main work area",
      "Cleaned out the sink",
      "Toured Jane. Loved the space, will likely sign up this week.",
      "Purchased 5 more stainless steel cups for water fill area. Spent $25.50.",
      "Renewed our business license.",
      "Morning walk-through. Did the dishes, turned on the lights & music, re-stocked snacks, & made a fresh pot of coffee. ",
      "New office signs arrived! ",
      "Took out the trash. ",
      "Gave a tour to a nice couple, Peg & John. Starting a new business and are new to coworking. ",
      "Wrote and posted a new blog article. ",
      "Deposited rent checks for Office 3 and Office 8. Spent $1278 total.",
      "Picked up new snacks at the store. Spent $88.24.",
      "Cleaned up a coffee spill in the hallway.",
      "Swept and vacuumed after group in conference room today. Left a mess.",
      "Printed out an invoice for Office 2 for their main office records",
      "Garbage can was overflowing. Took care of it. ",
      "Paid utility bill. $75.31.",
      "Set up yoga class in conference room for noon. Great attendance (11).",
      "Spoke with new UPS guy about how to deliver packages",
      "Cleaned dog nose prints off the front window",
      "Confirmed team retreat with the League in two weeks. ",
      "Member lunch today! Will pick up the tacos at 11:30am. ",
      "Ordered more snacks through Amazon. Spent $126.90, delivery set for Tuesday.",
      "Worked on printer jam! Again. ",
      "Got more printer paper. Spent $52.35",
      "Re-arranged the snack cabinet. ",
      "Out of pens - spent $22 on a big pack from Staples.",
      "Julie said she would love to hear more Jazz in the lobby. ",
      "Spent $72.36 on 6 bags of coffee. Have that team retreat coming in so need extra ready.",
      "Did the Friday fridge clean out. Nothing too gross thankfully",
      "Saw feedback about temperature. Checked thermostats and upped the temp a bit to see if it helps.",
      "Watered the plants in the lobby. ",
      "Lunch n’ Learn today - walked around and reminded members",
      "Onboarded our new full time desk member, Shane. ",
      "Stocked snacks and sodas (LaCroix)",
      "Decalcified Espresso Maker",
      "Joe is starting a new business, would love help thinking of names for it. ",
      "Raffled off tickets for TEDx to members - Brad & Jennifer are excited to be going.",
      "Ran a revenue report, we’re up 6% since last month!",
      "Gave a tour to Annie",
      "Helped set up A/V in conference room for Rotary",
      "Unloaded and reloaded the dish washer",
      "Call from BGC about donating a membership to their chairty event. Sent them one.",
      "Inventory check - will need more TP, Paper towels, and coffee next week.",
      "Rescheduled tour with Jim. Had something come up and couldn’t make it today. ",
      "Leon is moving out of his office today. Helped him carry stuff to his car.",
      "Got an email from a company looking for a private office. Gave them a call. Tour scheduled for this Thursday at 10am.",
      "Blake let me know he’s going to downgrade his membership for a month while traveling.",
      "Spent $25 on a thank you giftcard for Jill for helping me yesterday",
      "Fixed random table leg issue on desk 22",
      "Brad is super angry about someone drinking his beer. Offered to replace it for him."]
  end
end


