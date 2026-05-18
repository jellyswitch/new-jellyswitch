module Notes
  # Copies every LeadNote row into the equivalent polymorphic Note row.
  # Idempotent — re-running skips LeadNotes already migrated. Activity rows
  # are NOT re-written: every LeadNote already wrote an Activity(kind: :note)
  # at its own creation time, so the timeline already shows the note. We
  # suppress Note#after_create :log_activity during the copy to avoid a
  # second Activity row per note.
  #
  # The existing Activity rows still point at subject_type: "LeadNote".
  # PR 3 of the Lead deprecation work either repoints them at Note OR drops
  # the subject pointer entirely; either way the timeline display is
  # unaffected because the row is rendered from payload, not from subject.
  class BackfillFromLeadNotes
    def self.call
      created = 0
      skipped = 0

      LeadNote.includes(:lead, :user, :rich_text_content).find_each do |ln|
        notable = ln.lead&.user
        next if notable.nil?

        if Note.exists?(notable: notable, author: ln.user, created_at: ln.created_at)
          skipped += 1
          next
        end

        ActsAsTenant.with_tenant(ln.lead.operator) do
          Note.suppress_log_activity do
            Note.create!(
              notable: notable,
              operator: ln.lead.operator,
              author: ln.user,
              body: ln.content&.body&.to_html,
              created_at: ln.created_at,
              updated_at: ln.updated_at,
            )
          end
        end
        created += 1
      end

      { created: created, skipped: skipped }
    end
  end
end
