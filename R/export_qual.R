positives <- biweekly |>
  left_join(intake, by = "pid") |>
  filter(age <= 25 & qualified & employment == "Not currently employed") |>
  filter(!is.na(positives) & !positives == "") |>
  select(positives)

nrow(biweekly |> filter(!is.na(problematic_play)))

first_export <- read_csv("R/qual.csv")

qual <- dat_matched |>
  left_join(biweekly, by = "pid") |>
  filter(!problematic_play %in% c(NA, "") & !positives %in% c(NA, "")) |>
  select(
    pid,
    wave,
    age,
    gender,
    country,
    neet,
    employment,
    positives,
    problematic_play
  ) |>
  anti_join(first_export, by = c("pid", "wave"))

write_excel_csv(qual, "R/qual2.csv")
