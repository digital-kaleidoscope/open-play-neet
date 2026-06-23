# =============================================================================
# Helper functions for Open Play Demographics analysis
# =============================================================================

# -----------------------------------------------------------------------------
# TABLE FORMATTING
# -----------------------------------------------------------------------------

#' Format mean and standard deviation
#' @param x Numeric vector
#' @return Character string "M (SD)" or em-dash if empty
format_mean_sd <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0) {
    return("\u2014")
  }
  glue("{round(mean(x), 1)} ({round(sd(x), 1)})")
}

#' Format count and percentage
#' @param n Count
#' @param total Denominator for percentage
#' @return Character string "n (pct%)" with LaTeX-escaped percent sign
format_n_pct <- function(n, total) {
  if (n == 0) {
    return("0 (0.0\\%)")
  }
  glue("{n} ({round(100 * n / total, 1)}\\%)")
}

#' Create a table row with Total/US/UK columns
make_table_row <- function(char, val_total, val_us, val_uk) {
  tibble(Characteristic = char, Total = val_total, US = val_us, UK = val_uk)
}

#' Create categorical rows for demographics table
make_demo_rows <- function(data, var, label, levels, n_total, n_us, n_uk) {
  header <- make_table_row(glue("**{label}**"), "", "", "")

  rows <- map_dfr(levels, function(lvl) {
    n_tot <- sum(data[[var]] == lvl, na.rm = TRUE)
    n_us_val <- sum(data[[var]] == lvl & data$country == "US", na.rm = TRUE)
    n_uk_val <- sum(data[[var]] == lvl & data$country == "UK", na.rm = TRUE)
    make_table_row(
      glue("    {lvl}"),
      format_n_pct(n_tot, n_total),
      format_n_pct(n_us_val, n_us),
      format_n_pct(n_uk_val, n_uk)
    )
  })

  bind_rows(header, rows)
}

# -----------------------------------------------------------------------------
# GENRE ANALYSIS
# -----------------------------------------------------------------------------

#' Clean and collapse genre categories
clean_genre <- function(genre_raw) {
  case_when(
    genre_raw == "Indie" ~ NA_character_,
    genre_raw %in%
      c(
        "Turn-based strategy (TBS)",
        "Real Time Strategy (RTS)",
        "Tactical",
        "MOBA"
      ) ~ "Strategy",
    str_detect(genre_raw, "Hack and slash") ~ "Action",
    genre_raw == "Point-and-click" ~ "Adventure",
    genre_raw == "Visual Novel" ~ "Adventure",
    genre_raw == "Card & Board Game" ~ "Puzzle",
    genre_raw == "Quiz/Trivia" ~ "Puzzle",
    genre_raw == "Pinball" ~ "Arcade",
    genre_raw == "Music" ~ "Arcade",
    TRUE ~ genre_raw
  )
}

# --- Shared helpers ----------------------------------------------------------

#' Individual-level genre allocations (proportion of each person's playtime)
calc_individual_genre_props <- function(data) {
  data |>
    group_by(pid, genre_clean) |>
    summarise(genre_minutes = sum(minutes, na.rm = TRUE), .groups = "drop") |>
    group_by(pid) |>
    mutate(individual_prop = genre_minutes / sum(genre_minutes)) |>
    ungroup()
}

#' Individual genre proportions with 0-completion for unplayed genres
prep_genre_individual <- function(genre_by_demo) {
  ind <- calc_individual_genre_props(genre_by_demo)
  ind |>
    complete(
      pid,
      genre_clean = unique(ind$genre_clean),
      fill = list(individual_prop = 0)
    )
}

#' Map each player to their demographic groups in long format.
#' Handles neurodiversity non-exclusivity (a player can belong to multiple groups).
build_group_membership <- function(genre_by_demo) {
  demo <- genre_by_demo |>
    distinct(
      pid,
      age_group,
      gender,
      ethnicity,
      is_neurotypical,
      is_adhd,
      is_autism
    )

  bind_rows(
    demo |>
      filter(!is.na(age_group)) |>
      transmute(pid, demographic = "Age", group = age_group),
    demo |>
      filter(!is.na(gender)) |>
      transmute(pid, demographic = "Gender", group = gender),
    demo |>
      filter(!is.na(ethnicity)) |>
      transmute(pid, demographic = "Ethnicity", group = ethnicity),
    demo |>
      filter(is_neurotypical) |>
      transmute(pid, demographic = "Neurodiversity", group = "Neurotypical"),
    demo |>
      filter(is_adhd) |>
      transmute(pid, demographic = "Neurodiversity", group = "ADHD"),
    demo |>
      filter(is_autism) |>
      transmute(pid, demographic = "Neurodiversity", group = "ASD")
  )
}

# --- Genre proportions, sample sizes, and deviation ratios -------------------

#' Mean genre proportions across all demographic groups
build_genre_props <- function(genre_by_demo) {
  prep_genre_individual(genre_by_demo) |>
    inner_join(build_group_membership(genre_by_demo), by = "pid",
               relationship = "many-to-many") |>
    group_by(demographic, group, genre_clean) |>
    summarise(prop = mean(individual_prop), .groups = "drop") |>
    mutate(
      demographic = factor(
        demographic,
        levels = c("Age", "Gender", "Ethnicity", "Neurodiversity")
      )
    )
}

#' Sample sizes per demographic group
calc_group_ns <- function(genre_by_demo) {
  build_group_membership(genre_by_demo) |>
    distinct(pid, demographic, group) |>
    count(demographic, group, name = "n")
}

#' Leave-one-out deviation ratios for genre preferences.
#' Reference for each group = mean across all players NOT in that group.
#' Vectorised: LOO ref mean = (total_sum - focal_sum) / (total_n - focal_n).
calc_genre_deviation <- function(genre_by_demo, genre_props) {
  ind <- prep_genre_individual(genre_by_demo)
  membership <- build_group_membership(genre_by_demo)
  n_total <- n_distinct(ind$pid)

  # Sum of individual_prop across all players, per genre
  overall <- ind |>
    group_by(genre_clean) |>
    summarise(total_sum = sum(individual_prop), .groups = "drop")

  # Sum and count within each focal group
  focal <- ind |>
    inner_join(membership, by = "pid", relationship = "many-to-many") |>
    group_by(demographic, group, genre_clean) |>
    summarise(focal_sum = sum(individual_prop), focal_n = n(), .groups = "drop")

  genre_props |>
    left_join(focal, by = c("demographic", "group", "genre_clean")) |>
    left_join(overall, by = "genre_clean") |>
    mutate(
      ref_prop = (total_sum - focal_sum) / (n_total - focal_n),
      dev_ratio = prop / ref_prop,
      dev_ratio_capped = pmin(pmax(dev_ratio, 0.5), 2.0)
    ) |>
    select(-total_sum, -focal_sum, -focal_n)
}

# --- Genre deviation bar chart -----------------------------------------------

#' Shared theme for genre deviation bar panels
theme_genre_bar <- function() {
  theme_minimal(base_size = 10) +
    theme(
      panel.grid.major.y = element_blank(),
      panel.grid.minor = element_blank(),
      panel.border = element_rect(
        colour = "grey70",
        fill = NA,
        linewidth = 0.4
      ),
      strip.background = element_rect(fill = "black", colour = "black"),
      strip.text = element_text(colour = "white", face = "bold", size = 9),
      axis.text.x = element_text(size = 8),
      plot.margin = margin(0, 2, 0, 2, "pt")
    )
}

#' Mirrored bar chart grid of genre deviations across demographic groups.
#' Flat patchwork grid so rows align across columns of different lengths.
build_genre_bar_grid <- function(dev_data, ci_data, ns_data, group_colors) {
  demo_groups <- list(
    Age = c("18-24", "25-30", "31-35", "36-40"),
    Gender = c("Man", "Woman", "Non-binary"),
    Ethnicity = c("Asian", "Black", "Multiple", "Other", "White"),
    Neurodiversity = c("ADHD", "ASD", "Neurotypical")
  )
  max_rows <- max(lengths(demo_groups))
  n_cols <- length(demo_groups)

  log2_breaks <- log2(c(0.5, 1, 2))
  log2_labels <- c("0.5\u00d7", "1\u00d7", "2\u00d7")

  xlim <- log2(c(0.4, 2.5))

  # Pre-join everything so each panel just filters
  plot_data <- dev_data |>
    left_join(ci_data, by = c("demographic", "group", "genre_clean")) |>
    left_join(ns_data, by = c("demographic", "group")) |>
    mutate(
      log2_dev = log2(dev_ratio),
      log2_lo  = log2(ci_lo + 1),
      log2_hi  = log2(ci_hi + 1),
      genre_clean = fct_rev(genre_clean),
      strip_label = glue("{group}  (n = {scales::comma(n)})")
    )

  # y_side: "left"/"right" for native y-axis, "none" to suppress
  make_panel <- function(grp, demo, y_side = "none") {
    d <- plot_data |> filter(group == grp, as.character(demographic) == demo)

    p <- ggplot(d, aes(x = log2_dev, y = genre_clean)) +
      geom_col(fill = group_colors[grp], width = 0.7) +
      geom_errorbarh(aes(xmin = log2_lo, xmax = log2_hi),
                     height = 0.3, linewidth = 1.0, colour = "white") +
      geom_errorbarh(aes(xmin = log2_lo, xmax = log2_hi),
                     height = 0.3, linewidth = 0.35, colour = "grey20") +
      geom_vline(xintercept = 0, linewidth = 0.4, colour = "grey30") +
      scale_x_continuous(breaks = log2_breaks, labels = log2_labels) +
      coord_cartesian(xlim = xlim) +
      facet_wrap(~strip_label) +
      labs(y = NULL, x = NULL) +
      theme_genre_bar()

    if (y_side %in% c("left", "right")) {
      p <- p + scale_y_discrete(position = y_side) +
        theme(axis.text.y = element_text(size = 9))
    } else {
      p <- p + theme(axis.text.y = element_blank())
    }
    p
  }

  # Pre-build label-only plots (built outside pmap to avoid theme_void() scoping issue).
  # Text is positioned at the panel edge (x=1 right-flush, x=0 left-flush)
  # with zero expansion so labels sit adjacent to the neighbouring real panel.
  label_d <- plot_data |> distinct(genre_clean) |> mutate(strip_label = " ")
  label_theme <- ggplot2::theme_void() +
    theme(
      strip.background = element_rect(fill = "transparent", colour = "transparent"),
      strip.text = element_text(colour = "transparent", face = "bold", size = 8),
      plot.margin = margin(0, 2, 0, 2, "pt")
    )
  label_base <- ggplot(label_d, aes(y = genre_clean)) +
    scale_x_continuous(limits = c(0, 1), expand = expansion(0, 0)) +
    facet_wrap(~strip_label) + labs(x = NULL, y = NULL) + label_theme
  label_panel_right <- label_base +
    geom_text(aes(x = 1, label = genre_clean), hjust = 1, size = 9 / .pt, colour = "grey20")
  label_panel_left <- label_base +
    geom_text(aes(x = 0, label = genre_clean), hjust = 0, size = 9 / .pt, colour = "grey20")

  # Row-major flat grid — classify each cell
  grid <- expand_grid(row = seq_len(max_rows), col = seq_len(n_cols)) |>
    mutate(
      demo = names(demo_groups)[col],
      grp = map2_chr(demo, row, \(d, r) {
        g <- demo_groups[[d]]; if (r <= length(g)) g[r] else NA_character_
      })
    ) |>
    group_by(row) |>
    mutate(
      is_real    = !is.na(grp),
      left_edge  = min(col[is_real]),
      right_edge = max(col[is_real]),
      cell_type = case_when(
        # Real panels: native axis only on outermost columns
        is_real & col == 1      ~ "axis_left",
        is_real & col == n_cols ~ "axis_right",
        is_real                 ~ "no_axis",
        # Label plots in spacers adjacent to edge panels missing native axis
        !is_real & left_edge > 1      & col == left_edge - 1  ~ "label_right",
        !is_real & right_edge < n_cols & col == right_edge + 1 ~ "label_left",
        TRUE ~ "spacer"
      )
    ) |>
    ungroup()

  panels <- pmap(grid, function(row, col, demo, grp, is_real,
                                left_edge, right_edge, cell_type) {
    switch(cell_type,
      axis_left   = make_panel(grp, demo, "left"),
      axis_right  = make_panel(grp, demo, "right"),
      no_axis     = make_panel(grp, demo, "none"),
      label_right = label_panel_right,
      label_left  = label_panel_left,
      patchwork::plot_spacer()
    )
  })

  patchwork::wrap_plots(panels, ncol = n_cols)
}

# --- Bootstrap confidence intervals ------------------------------------------

#' Bootstrap 95% CIs for genre deviation ratios.
#' Uses boot::boot with stratified resampling to independently resample
#' focal and reference groups each iteration.
bootstrap_genre_ci <- function(genre_by_demo, n_boot = 1000, seed = 42) {
  set.seed(seed)
  ind <- prep_genre_individual(genre_by_demo)
  membership <- build_group_membership(genre_by_demo)
  genres <- sort(unique(ind$genre_clean))

  # Wide matrix for fast resampling (rows = pids, cols = genres)
  prop_wide <- ind |>
    select(pid, genre_clean, individual_prop) |>
    pivot_wider(
      names_from = genre_clean,
      values_from = individual_prop,
      values_fill = 0
    )
  all_pids <- prop_wide$pid
  mat <- prop_wide |> select(-pid) |> as.matrix()
  mat <- mat[, genres, drop = FALSE]

  groups <- membership |> distinct(demographic, group)

  map2_dfr(groups$demographic, groups$group, function(d, g) {
    focal_pids <- membership |>
      filter(demographic == d, group == g) |>
      pull(pid) |>
      unique()
    is_focal <- all_pids %in% focal_pids

    # Stratified bootstrap: focal and reference resampled independently
    boot_stat <- function(data, idx) {
      d <- data[idx, , drop = FALSE]
      f_mean <- colMeans(d[is_focal, , drop = FALSE])
      r_mean <- colMeans(d[!is_focal, , drop = FALSE])
      ifelse(r_mean == 0, NA_real_, f_mean / r_mean)
    }

    b <- boot::boot(mat, boot_stat, R = n_boot, strata = factor(is_focal))

    tibble(
      genre_clean = genres,
      ci_lo = apply(b$t, 2, quantile, probs = 0.025, na.rm = TRUE) - 1,
      ci_hi = apply(b$t, 2, quantile, probs = 0.975, na.rm = TRUE) - 1
    ) |>
      mutate(demographic = d, group = g)
  })
}
