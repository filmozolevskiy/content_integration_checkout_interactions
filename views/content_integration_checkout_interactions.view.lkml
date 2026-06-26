view: content_integration_checkout_interactions {
  sql_table_name: ota.bookability_checkout_interactions ;;

  # -------------------------
  # Keys (hidden)
  # -------------------------

  dimension: id {
    primary_key: yes
    type: number
    sql: ${TABLE}.id ;;
    hidden: yes
  }

  # -------------------------
  # 1. DATE
  # -------------------------

  dimension_group: created {
    type: time
    timeframes: [raw, time, date, week, month, quarter, year]
    sql: ${TABLE}.date_created ;;
    group_label: "1. DATE"
    label: "Created"
    description: "When the checkout interaction was logged (ota.bookability_checkout_interactions.date_created). The time axis for every trend."
  }

  # -------------------------
  # 2. EVENT
  # -------------------------

  dimension: event {
    type: string
    sql: ${TABLE}.event ;;
    group_label: "2. EVENT"
    label: "Event"
    description: "Checkout interaction type. error_type is populated only on 'error_displayed'."
    suggestions: [
      "booking_attempt_launched",
      "error_displayed",
      "fare_increase_displayed",
      "fare_increase_accepted",
      "fare_increase_denied",
      "generic_error_displayed",
      "allowed_attempt_displayed_price_discrepancy",
      "allowed_locked_package_book_attempt",
      "blocked_locked_package_book_attempt",
      "time_lapse_session_expired"
    ]
  }

  dimension: is_error {
    type: yesno
    sql: ${event} IN ('error_displayed', 'generic_error_displayed') ;;
    group_label: "2. EVENT"
    label: "Is Error"
    description: "True when the event is an error display (error_displayed or generic_error_displayed)."
  }

  # -------------------------
  # 3. ERROR
  # -------------------------

  dimension: error_type {
    type: string
    sql: JSON_UNQUOTE(JSON_EXTRACT(${TABLE}.payload, '$.error_type')) ;;
    group_label: "3. ERROR"
    label: "Error Type"
    description: "Error classification from payload.error_type. Set only on 'error_displayed' events; NULL otherwise."
    suggestions: [
      "three_ds_requires_action",
      "flight_unavailable",
      "fraud_check_red_zone",
      "fraud_check_cc_problem",
      "fraud_check_cvv",
      "fare_change",
      "cc_payment_declined",
      "session_expired",
      "duplicate_booking",
      "validation",
      "gds_error",
      "unknown_error",
      "pricing_error",
      "fare_increase_not_allowed",
      "locked_package",
      "unbookable_package"
    ]
  }

  dimension: error_category {
    type: string
    group_label: "3. ERROR"
    label: "Error Category"
    description: "Coarse grouping of error_type into fraud / payment / availability / fare / validation / session / duplicate / gds / locked / other."
    case: {
      when: { sql: ${error_type} IN ('fraud_check_red_zone', 'fraud_check_cc_problem', 'fraud_check_cvv') ;; label: "Fraud" }
      when: { sql: ${error_type} IN ('cc_payment_declined', 'three_ds_requires_action') ;; label: "Payment" }
      when: { sql: ${error_type} IN ('flight_unavailable', 'unbookable_package') ;; label: "Availability" }
      when: { sql: ${error_type} IN ('fare_change', 'pricing_error', 'fare_increase_not_allowed') ;; label: "Fare" }
      when: { sql: ${error_type} = 'validation' ;; label: "Validation" }
      when: { sql: ${error_type} = 'session_expired' ;; label: "Session" }
      when: { sql: ${error_type} = 'duplicate_booking' ;; label: "Duplicate" }
      when: { sql: ${error_type} = 'gds_error' ;; label: "GDS" }
      when: { sql: ${error_type} = 'locked_package' ;; label: "Locked Package" }
      when: { sql: ${error_type} = 'unknown_error' ;; label: "Unknown" }
      else: "Other / No Error"
    }
  }

  # -------------------------
  # 4. VALIDATION (validation errors only)
  # -------------------------
  # The three fields below read payload.user_error_display, which exists ONLY on
  # error_displayed events whose error_type = 'validation'. They are NULL on every
  # other event/error_type. Filter to error_type: "validation" (or use the
  # validation_count measure) before slicing by them.

  dimension: validation_fields {
    type: string
    sql: REPLACE(REPLACE(REPLACE(JSON_KEYS(JSON_EXTRACT(${TABLE}.payload, '$.user_error_display')), '"', ''), '[', ''), ']', '') ;;
    group_label: "4. VALIDATION"
    label: "Validation Fields"
    description: "Validation errors only. Comma-separated list of every form field that failed validation in this event (e.g. 'p4_dob_day, p4_dob_month, p4_dob_year'). NULL on non-validation events."
  }

  dimension: validation_values {
    type: string
    # Why (2026-06-26, FM): each failing field object is {"value": "<user input>"?, "server_*": "<message>"}.
    # The user's typed value lives under the "value" key when captured. Unnest every field's value and
    # join the distinct set so multi-field validations (e.g. DOB triples) are shown in full.
    sql: (
      SELECT GROUP_CONCAT(DISTINCT vv ORDER BY vv SEPARATOR ' | ')
      FROM JSON_TABLE(
        COALESCE(JSON_EXTRACT(${TABLE}.payload, '$.user_error_display.*.value'), JSON_ARRAY()),
        '$[*]' COLUMNS (vv VARCHAR(500) PATH '$')
      ) vals
    ) ;;
    group_label: "4. VALIDATION"
    label: "Validation Values (User Input)"
    description: "Validation errors only. Distinct values the customer typed into the failing fields, joined with ' | '. NULL on non-validation events, or when no field captured a value. Free text — use for drill-down, not grouping. Credit card numbers arrive pre-masked as <masked-value>."
  }

  dimension: validation_messages {
    type: string
    # Why (2026-06-26, FM): messages are every leaf under user_error_display EXCEPT the user's typed
    # "value" entries. Unnest all leaves, drop the ones that match the value array, join the distinct set.
    sql: (
      SELECT GROUP_CONCAT(DISTINCT lf ORDER BY lf SEPARATOR ' | ')
      FROM JSON_TABLE(
        JSON_EXTRACT(${TABLE}.payload, '$.user_error_display.*.*'),
        '$[*]' COLUMNS (lf VARCHAR(500) PATH '$')
      ) leaves
      WHERE lf NOT IN (
        SELECT vv2 FROM JSON_TABLE(
          COALESCE(JSON_EXTRACT(${TABLE}.payload, '$.user_error_display.*.value'), JSON_ARRAY()),
          '$[*]' COLUMNS (vv2 VARCHAR(500) PATH '$')
        ) vals2
      )
    ) ;;
    group_label: "4. VALIDATION"
    label: "Validation Messages"
    description: "Validation errors only. Distinct validation messages shown to the customer, joined with ' | ' (e.g. 'Invalid postal code'). NULL on non-validation events. Captures every field's message for multi-field validations. Raw user input excluded."
  }

  # -------------------------
  # 5. FUNNEL KEYS
  # -------------------------

  dimension: checkout_id {
    type: string
    sql: ${TABLE}.checkout_id ;;
    group_label: "5. FUNNEL KEYS"
    label: "Checkout ID"
    description: "Groups all interaction events for one checkout session."
  }

  dimension: search_id {
    type: string
    sql: ${TABLE}.search_id ;;
    group_label: "5. FUNNEL KEYS"
    label: "Search ID"
    description: "Search hash the checkout originated from."
  }

  dimension: package_id {
    type: string
    sql: ${TABLE}.package_id ;;
    group_label: "5. FUNNEL KEYS"
    label: "Package ID"
    description: "Selected fare package for the checkout."
  }

  dimension: surfer_id {
    type: string
    sql: ${TABLE}.surfer_id ;;
    group_label: "5. FUNNEL KEYS"
    label: "Surfer ID"
    description: "Unique customer/session identifier."
  }

  dimension: customer_attempt_id {
    type: number
    sql: ${TABLE}.customer_attempt_id ;;
    group_label: "5. FUNNEL KEYS"
    label: "Customer Attempt ID"
    description: "FK to bookability_customer_attempts.id. Populated on only ~34% of rows; NULL when the event has no linked booking attempt."
  }

  # -------------------------
  # 6. PAYLOAD METRICS
  # -------------------------

  dimension: price_difference {
    type: number
    sql: CAST(JSON_UNQUOTE(JSON_EXTRACT(${TABLE}.payload, '$.price_difference')) AS DECIMAL(12,2)) ;;
    group_label: "6. PAYLOAD METRICS"
    label: "Price Difference"
    description: "Fare delta shown to the customer, from payload.price_difference. Set on 'fare_increase_displayed' events."
    value_format: "#,##0.00"
  }

  # -------------------------
  # Measures
  # -------------------------

  measure: count {
    type: count
    label: "Interaction Count"
    description: "Total checkout interaction events matching the current filters."
    group_label: "7. COUNTS"
  }

  measure: checkouts {
    type: count_distinct
    sql: ${checkout_id} ;;
    label: "Checkouts"
    description: "Distinct checkout sessions (checkout_id)."
    group_label: "7. COUNTS"
  }

  measure: surfers {
    type: count_distinct
    sql: ${surfer_id} ;;
    label: "Surfers"
    description: "Distinct customers/sessions (surfer_id)."
    group_label: "7. COUNTS"
  }

  measure: searches {
    type: count_distinct
    sql: ${search_id} ;;
    label: "Searches"
    description: "Distinct searches (search_id) behind the interactions."
    group_label: "7. COUNTS"
  }

  measure: error_count {
    type: count
    label: "Error Count"
    description: "Count of error-display events (error_displayed or generic_error_displayed)."
    filters: [is_error: "yes"]
    group_label: "8. ERROR METRICS"
  }

  measure: launched_count {
    type: count
    label: "Booking Attempts Launched"
    description: "Count of booking_attempt_launched events — the denominator for error rate."
    filters: [event: "booking_attempt_launched"]
    group_label: "8. ERROR METRICS"
  }

  measure: error_rate {
    type: number
    sql: 1.0 * ${error_count} / NULLIF(${launched_count}, 0) ;;
    label: "Error Rate"
    description: "Error displays per booking attempt launched (error_count / launched_count). Above 1.0 is possible — one attempt can surface several errors."
    value_format: "0.0%"
    group_label: "8. ERROR METRICS"
  }

  measure: validation_count {
    type: count
    label: "Validation Error Count"
    description: "Count of error displays whose error_type is 'validation' (form-field validation failures)."
    filters: [error_type: "validation"]
    group_label: "8. ERROR METRICS"
  }
}
