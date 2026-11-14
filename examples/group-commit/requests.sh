# The requests scripts/test-examples.sh sends to this example, in order.
req GET /health
# Each note is answered once its pass has committed it.
req POST /notes -d 'first note'
req POST /notes -d 'second note'
req POST /notes -d ''
req GET /notes
req GET /stats
