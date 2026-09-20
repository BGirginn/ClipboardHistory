length == 1 and
(.[0] as $metric |
  $metric.itemCount == 5000 and
  ($metric.repetitions | type) == "number" and
  $metric.repetitions >= 100 and
  ([$metric.writeP95Ms, $metric.readP95Ms, $metric.modelLoadP95Ms,
    $metric.filterP95Ms, $metric.layoutP95Ms]
    | all(.[]; type == "number" and . >= 0)) and
  $metric.writeP95Ms <= 100 and
  $metric.readP95Ms <= 50 and
  $metric.modelLoadP95Ms <= 100 and
  $metric.filterP95Ms <= 50 and
  $metric.layoutP95Ms <= 50)
