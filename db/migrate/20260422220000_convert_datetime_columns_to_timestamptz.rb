class ConvertDatetimeColumnsToTimestamptz < ActiveRecord::Migration[7.1]
  # Convert reservations.datetime_in and checkins.datetime_in/out from
  # `timestamp without time zone` to `timestamp with time zone`.
  #
  # Existing values are naive wall-clock times in the location's local zone —
  # NOT UTC. We interpret each row's naive value through the linked location's
  # time_zone so the stored UTC instant matches the wall-clock the member
  # actually picked.
  #
  # Postgres rejects correlated subqueries in `USING` expressions and Rails
  # stores TZ as friendly names ("Pacific Time (US & Canada)") while PG needs
  # IANA ("America/Los_Angeles"), so we install a temp function that does the
  # lookup + mapping. Orphan reservations (room_id pointing to a deleted
  # room) and any other lookup failure fall back to UTC — preserves the
  # stored digits, keeps the NOT NULL constraint happy. Verified against
  # prod data: only "Pacific Time (US & Canada)" (11 locations) and
  # "Central Time (US & Canada)" (1 location) are actually in use.
  #
  # The ALTERs run inside a transaction (Rails default); any failure rolls
  # back all column changes and no data is altered.

  RAILS_TO_IANA_CASE = <<~SQL.freeze
    CASE tz_name
      WHEN 'Pacific Time (US & Canada)' THEN 'America/Los_Angeles'
      WHEN 'Central Time (US & Canada)' THEN 'America/Chicago'
      WHEN 'Mountain Time (US & Canada)' THEN 'America/Denver'
      WHEN 'Eastern Time (US & Canada)' THEN 'America/New_York'
      WHEN 'Arizona'                     THEN 'America/Phoenix'
      WHEN 'Hawaii'                      THEN 'Pacific/Honolulu'
      WHEN 'Alaska'                      THEN 'America/Anchorage'
      ELSE 'UTC'
    END
  SQL

  def up
    execute(<<~SQL)
      CREATE OR REPLACE FUNCTION _tmp_tz_for_room(rid integer) RETURNS text LANGUAGE sql STABLE AS $fn$
        SELECT COALESCE((
          SELECT #{RAILS_TO_IANA_CASE.gsub('tz_name', 'l.time_zone')}
          FROM rooms r JOIN locations l ON l.id = r.location_id
          WHERE r.id = rid
        ), 'UTC');
      $fn$;
    SQL

    execute(<<~SQL)
      CREATE OR REPLACE FUNCTION _tmp_tz_for_location(lid integer) RETURNS text LANGUAGE sql STABLE AS $fn$
        SELECT COALESCE((
          SELECT #{RAILS_TO_IANA_CASE.gsub('tz_name', 'l.time_zone')}
          FROM locations l WHERE l.id = lid
        ), 'UTC');
      $fn$;
    SQL

    execute(<<~SQL)
      ALTER TABLE reservations
      ALTER COLUMN datetime_in TYPE timestamp with time zone
      USING datetime_in AT TIME ZONE _tmp_tz_for_room(room_id);
    SQL

    execute(<<~SQL)
      ALTER TABLE checkins
      ALTER COLUMN datetime_in TYPE timestamp with time zone
      USING datetime_in AT TIME ZONE _tmp_tz_for_location(location_id);
    SQL

    execute(<<~SQL)
      ALTER TABLE checkins
      ALTER COLUMN datetime_out TYPE timestamp with time zone
      USING CASE
        WHEN datetime_out IS NULL THEN NULL
        ELSE datetime_out AT TIME ZONE _tmp_tz_for_location(location_id)
      END;
    SQL

    execute("DROP FUNCTION _tmp_tz_for_room(integer);")
    execute("DROP FUNCTION _tmp_tz_for_location(integer);")
  end

  def down
    execute(<<~SQL)
      CREATE OR REPLACE FUNCTION _tmp_tz_for_room(rid integer) RETURNS text LANGUAGE sql STABLE AS $fn$
        SELECT COALESCE((
          SELECT #{RAILS_TO_IANA_CASE.gsub('tz_name', 'l.time_zone')}
          FROM rooms r JOIN locations l ON l.id = r.location_id
          WHERE r.id = rid
        ), 'UTC');
      $fn$;
    SQL

    execute(<<~SQL)
      CREATE OR REPLACE FUNCTION _tmp_tz_for_location(lid integer) RETURNS text LANGUAGE sql STABLE AS $fn$
        SELECT COALESCE((
          SELECT #{RAILS_TO_IANA_CASE.gsub('tz_name', 'l.time_zone')}
          FROM locations l WHERE l.id = lid
        ), 'UTC');
      $fn$;
    SQL

    execute(<<~SQL)
      ALTER TABLE checkins
      ALTER COLUMN datetime_out TYPE timestamp without time zone
      USING CASE
        WHEN datetime_out IS NULL THEN NULL
        ELSE datetime_out AT TIME ZONE _tmp_tz_for_location(location_id)
      END;
    SQL

    execute(<<~SQL)
      ALTER TABLE checkins
      ALTER COLUMN datetime_in TYPE timestamp without time zone
      USING datetime_in AT TIME ZONE _tmp_tz_for_location(location_id);
    SQL

    execute(<<~SQL)
      ALTER TABLE reservations
      ALTER COLUMN datetime_in TYPE timestamp without time zone
      USING datetime_in AT TIME ZONE _tmp_tz_for_room(room_id);
    SQL

    execute("DROP FUNCTION _tmp_tz_for_room(integer);")
    execute("DROP FUNCTION _tmp_tz_for_location(integer);")
  end
end
