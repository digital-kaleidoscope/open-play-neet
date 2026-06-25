positives <- biweekly |>
  left_join(intake, by = "pid") |>
  filter(age <= 25 & qualified & employment == "Not currently employed") |>
  filter(!is.na(positives) & !positives == "") |>
  select(positives)

nrow(biweekly |> filter(!is.na(problematic_play)))
