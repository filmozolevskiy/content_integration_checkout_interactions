connection: "ota"

include: "/views/**/*.view.lkml"

# Cache for ~1h — ota is read-only (no PDT), so this is query-result caching only.
datagroup: checkout_interactions_default {
  max_cache_age: "1 hour"
}

persist_with: checkout_interactions_default

explore: content_integration_checkout_interactions {
  label: "Checkout Interactions"
  description: "Customer-side checkout event log (ota.bookability_checkout_interactions). Error-type breakdown over time."

  always_filter: {
    filters: [content_integration_checkout_interactions.created_date: "7 days"]
  }
}
