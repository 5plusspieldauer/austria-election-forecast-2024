
theme_forecast <- function(base_size = 12){
  theme_minimal(base_size = base_size) +
    theme(plot.title = element_text(face = "bold"),
          plot.title.position = "plot",
          plot.caption = element_text(colour = "grey45", hjust = 0),
          plot.caption.position = "plot",
          panel.grid.minor = element_blank(),
          plot.background = element_rect(fill = "white", colour = NA))
}

theme_map <- function(base_size = 12){
  theme_void(base_size = base_size) +
    theme(plot.title = element_text(face = "bold", hjust = 0.5),
          plot.subtitle = element_text(hjust = 0.5),
          plot.background = element_rect(fill = "white", colour = NA),
          legend.position = "right")
}

save_fig <- function(plot, file, width = 8, height = 4.5, dpi = 200){
  ggsave(file.path("figures", file), plot, width = width, height = height, dpi = dpi, device = ragg::agg_png)
}

# Regional electoral districts (Regionalwahlkreise) with the GKZ used in the BMI result files
read_rwk_shapes <- function(){
  sf::read_sf("data/shapefiles/regionalwahlkreisgrenzen/STATISTIK_AUSTRIA_RWK_20240101.shp") %>%
    select(-g_name) %>%
    mutate(GKZ = paste0("G", g_id, "000"))
}

# Seat coordinates for a hemicycle: seats are filled row by row from the inner arc outwards, then ordered by angle
# so that parties occupy contiguous wedges from left to right.
parliament_coords <- function(n_seats = 183, n_rows = 8, r0 = 1, r1 = 2.2){
  radii <- seq(r0, r1, length.out = n_rows)
  per_row <- round(n_seats * radii / sum(radii))
  per_row[n_rows] <- per_row[n_rows] + (n_seats - sum(per_row))

  map2(radii, per_row, \(r, k) tibble(r = r, theta = seq(pi, 0, length.out = k))) %>%
    list_rbind() %>%
    mutate(x = r * cos(theta), y = r * sin(theta)) %>%
    arrange(desc(theta), r) %>%
    mutate(seat = row_number())
}

# One row per seat, assigned to parties in the given (left-to-right) order
hemicycle_data <- function(seats, party_levels){
  seats <- seats %>%
    filter(seats > 0) %>%
    mutate(party = factor(party, levels = party_levels)) %>%
    arrange(party)

  parliament_coords(sum(seats$seats)) %>%
    mutate(party = rep(seats$party, seats$seats))
}
