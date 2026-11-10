suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(cowplot)
  library(patchwork)
  library(scales)
  library(sf)
})

pdf(NULL)
out_dir <- "output/figures"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

states_info <- read.csv("data/raw/states.csv")
costs <- read.csv("data/derived/freight_costs.csv")
trade <- read.csv("data/derived/trade_flows.csv") %>% filter(year == 2022)
results <- read.csv("data/derived/counterfactual_states.csv") %>% filter(abs(theta - 4.14) < 1e-9)
contiguity <- read.csv("data/raw/contiguity.csv")
contiguity <- bind_rows(contiguity %>% transmute(origin = state1, destination = state2),
                        contiguity %>% transmute(origin = state2, destination = state1)) %>%
  mutate(C_ij = 1L)

scenarios_dr  <- c("real", "pop", "str")
scenarios_ndr <- c("auto")
scenarios     <- c(scenarios_dr, scenarios_ndr)
labels_dr     <- c("Existing Charging Network", "Population-Center Expansion", "Strategic Network Expansion")
labels_ndr    <- c("Strategic Network + Autonomy")

exports_bln <- trade %>%
  filter(origin != destination) %>%
  group_by(origin) %>%
  summarise(exports_BLN = sum(trade) / 1000, .groups = "drop")

states <- usmap::us_map(regions = "states") %>%
  rename(STUSPS = abbr, NAME = full) %>%
  filter(!STUSPS %in% c("AK", "HI", "DC"))
states <- st_transform(states, crs = "+proj=aea +lat_1=29.5 +lat_2=45.5 +lat_0=37.5 +lon_0=-96 +datum=NAD83")
states <- st_make_valid(states)
us_outline <- st_union(states)
state_name_map <- states %>%
  st_drop_geometry() %>%
  select(STUSPS, NAME) %>%
  mutate(key = gsub(" ", "_", toupper(NAME)))


make_ticks <- function(state1_abbr, state2_abbr, states_sf, tick_length = 18000, spacing = 12000) {
  s1 <- states_sf %>% filter(STUSPS == state1_abbr)
  s2 <- states_sf %>% filter(STUSPS == state2_abbr)
  border <- tryCatch({
    g1 <- st_make_valid(st_geometry(s1))
    g2 <- st_make_valid(st_geometry(s2))
    st_intersection(g1, g2)
  }, error = function(e) NULL)
  if (is.null(border) || length(border) == 0) return(NULL)
  border_lines <- tryCatch({
    st_cast(st_line_merge(st_union(border)), "LINESTRING")
  }, error = function(e) NULL)
  if (is.null(border_lines) || length(border_lines) == 0) return(NULL)
  total_length <- sum(as.numeric(st_length(border_lines)))
  n_pts <- max(2, floor(total_length / spacing))
  line_lengths <- as.numeric(st_length(border_lines))
  pts_coords <- do.call(rbind, lapply(seq_along(border_lines), function(i) {
    n_i <- max(1, round(n_pts * line_lengths[i] / total_length))
    st_coordinates(st_line_sample(border_lines[i], n = n_i))
  }))
  if (is.null(pts_coords) || nrow(pts_coords) == 0) return(NULL)
  full_coords <- st_coordinates(border_lines)
  get_angle <- function(px, py, coords) {
    dists <- sqrt((coords[, 1] - px)^2 + (coords[, 2] - py)^2)
    idx <- which.min(dists)
    if (idx >= nrow(coords)) idx <- nrow(coords) - 1
    if (idx < 1) idx <- 1
    atan2(coords[idx + 1, 2] - coords[idx, 2], coords[idx + 1, 1] - coords[idx, 1])
  }
  lines_list <- lapply(1:nrow(pts_coords), function(k) {
    px <- pts_coords[k, 1]; py <- pts_coords[k, 2]
    perp <- get_angle(px, py, full_coords) + pi / 2
    x0 <- px - cos(perp) * tick_length / 2
    y0 <- py - sin(perp) * tick_length / 2
    x1 <- px + cos(perp) * tick_length / 2
    y1 <- py + sin(perp) * tick_length / 2
    st_linestring(matrix(c(x0, y0, x1, y1), nrow = 2, byrow = TRUE))
  })
  st_sf(geometry = st_sfc(lines_list, crs = st_crs(states_sf)))
}

get_solid_borders <- function(disc_list, states_sf) {
  n <- nrow(states_sf)
  solid_lines <- list()
  for (i in 1:(n - 1)) {
    for (j in (i + 1):n) {
      ab <- states_sf$STUSPS[i]; ba <- states_sf$STUSPS[j]
      is_disc <- if (length(disc_list) == 0) FALSE else {
        any(sapply(disc_list, function(p) {
          !is.null(p) && length(p) == 2 && ((p[1] == ab & p[2] == ba) | (p[1] == ba & p[2] == ab))
        }), na.rm = TRUE)
      }
      if (is_disc) next
      shared <- tryCatch({
        g1 <- st_make_valid(st_geometry(states_sf[i, ]))
        g2 <- st_make_valid(st_geometry(states_sf[j, ]))
        st_intersection(g1, g2)
      }, error = function(e) NULL)
      if (is.null(shared) || length(shared) == 0) next
      shared_line <- tryCatch(st_cast(shared, "MULTILINESTRING"), error = function(e) NULL)
      if (is.null(shared_line)) next
      solid_lines[[length(solid_lines) + 1]] <- st_sf(state1 = ab, state2 = ba, geometry = shared_line)
    }
  }
  if (length(solid_lines) == 0) return(NULL)
  do.call(rbind, solid_lines)
}

pair_status <- function(s) {
  costs %>%
    select(key_i = origin, key_j = destination, indicator = all_of(paste0("status_", s))) %>%
    left_join(contiguity, by = c("key_i" = "origin", "key_j" = "destination")) %>%
    mutate(C_ij = coalesce(C_ij, 0L)) %>%
    left_join(state_name_map %>% rename(stusps_i = STUSPS), by = c("key_i" = "key")) %>%
    left_join(state_name_map %>% rename(stusps_j = STUSPS), by = c("key_j" = "key"))
}

reach_score <- function(df_conn) {
  df_conn %>%
    filter(connected == TRUE, key_i != key_j, !is.na(stusps_i), !is.na(stusps_j)) %>%
    left_join(exports_bln, by = c("key_j" = "origin")) %>%
    filter(!is.na(exports_BLN)) %>%
    group_by(stusps_i) %>%
    summarise(blue_score = sum(exports_BLN, na.rm = TRUE), .groups = "drop")
}

all_scores <- list()
for (s in scenarios) {
  df_ind <- pair_status(s)
  for (panel in c("AB", "B_only")) {
    df_conn <- df_ind %>% mutate(connected = if (panel == "AB") indicator >= 1 else indicator == 2)
    all_scores[[paste(s, panel)]] <- reach_score(df_conn)$blue_score
  }
}
global_min <- 0
global_max <- max(unlist(all_scores), na.rm = TRUE)

make_connection_panel <- function(s, panel) {
  df_ind <- pair_status(s)
  df_conn <- if (panel == "AB") df_ind %>% mutate(connected = indicator >= 1) else df_ind %>% mutate(connected = indicator == 2)
  disc_pairs_df <- df_conn %>%
    filter(C_ij == 1, indicator == 0, !is.na(stusps_i), !is.na(stusps_j)) %>%
    rowwise() %>%
    mutate(p1 = min(stusps_i, stusps_j), p2 = max(stusps_i, stusps_j)) %>%
    ungroup() %>%
    distinct(p1, p2)
  disc_pairs_list <- if (nrow(disc_pairs_df) > 0) {
    lapply(1:nrow(disc_pairs_df), function(i) c(disc_pairs_df$p1[i], disc_pairs_df$p2[i]))
  } else list()
  solid_sf <- get_solid_borders(disc_pairs_list, states)
  all_ticks <- if (length(disc_pairs_list) > 0) {
    do.call(rbind, lapply(disc_pairs_list, function(p) make_ticks(p[1], p[2], states)))
  } else NULL
  blue_score <- reach_score(df_conn) %>% rename(STUSPS = stusps_i)
  states_plot <- states %>% left_join(blue_score, by = "STUSPS")
  ggplot() +
    geom_sf(data = states_plot, aes(fill = blue_score), color = "black", linewidth = 0.4, linetype = "dashed") +
    scale_fill_gradient(low = "#c6dbef", high = "#08306b", na.value = "grey90",
                        name = "Exports (value, in Billion USD)", limits = c(global_min, global_max),
                        labels = scales::comma) +
    geom_sf(data = solid_sf, color = "black", linewidth = 0.4, linetype = "solid") +
    geom_sf(data = us_outline, fill = NA, color = "black", linewidth = 0.4) +
    {if (!is.null(all_ticks) && nrow(all_ticks) > 0) geom_sf(data = all_ticks, color = "red", linewidth = 0.7)} +
    coord_sf(datum = NA) +
    theme_void() +
    theme(legend.position = "none", plot.margin = margin(2, 2, 2, 2))
}

legend_plot <- make_connection_panel(scenarios[1], "AB") +
  theme(legend.position = "bottom", legend.title = element_text(size = 14), legend.text = element_text(size = 12)) +
  guides(fill = guide_colorbar(direction = "horizontal", title.position = "top", title.hjust = 0.5,
                               barwidth = 40, barheight = 1.0))
shared_legend <- get_legend(legend_plot)

panel_list <- list()
for (s in scenarios) {
  panel_list[[length(panel_list) + 1]] <- make_connection_panel(s, "AB")
  panel_list[[length(panel_list) + 1]] <- make_connection_panel(s, "B_only")
}
row_labels_2line <- c("Existing Charging\nNetwork", "Population-Center\nExpansion",
                      "Strategic Network\nExpansion", "Strategic Network\n+ Autonomy")
grid_panels <- plot_grid(plotlist = panel_list, nrow = 4, ncol = 2)
row_labels <- plot_grid(plotlist = lapply(row_labels_2line, function(s)
  ggdraw() + draw_label(s, fontface = "bold", size = 15, angle = 90, lineheight = 0.95)), ncol = 1)
body <- plot_grid(row_labels, grid_panels, nrow = 1, rel_widths = c(0.075, 1))
connection_plot <- plot_grid(
  ggdraw() +
    draw_label("(a) Connectivity", x = 0.30, y = 0.5, fontface = "bold", size = 14) +
    draw_label("(b) Adoption", x = 0.76, y = 0.5, fontface = "bold", size = 14),
  plot_grid(body, shared_legend, ncol = 1, rel_heights = c(1, 0.12)),
  ncol = 1, rel_heights = c(0.03, 1))
ggsave(file.path(out_dir, "combined_connection_adoption.png"), connection_plot, width = 11, height = 13, dpi = 300, bg = "white")


HOST <- states_info$state[states_info$strategic_host == 1]
it <- costs %>%
  filter(origin != destination) %>%
  select(key_i = origin, key_j = destination, status_pop, status_str) %>%
  left_join(trade %>% select(key_i = origin, key_j = destination, trade_BLN = trade), by = c("key_i", "key_j"))
new <- it %>% filter(status_pop == 0, status_str > 0)
NV <- sum(new$trade_BLN)
share <- bind_rows(new %>% transmute(key = key_i, exp = trade_BLN, imp = 0),
                   new %>% transmute(key = key_j, exp = 0, imp = trade_BLN)) %>%
  group_by(key) %>%
  summarise(exp = sum(exp), imp = sum(imp), .groups = "drop") %>%
  mutate(share = (exp + imp) / (2 * NV) * 100,
         share_exporter = exp / NV * 100,
         host = key %in% HOST) %>%
  arrange(desc(share))

host_states <- states %>%
  mutate(key = gsub(" ", "_", toupper(NAME))) %>%
  left_join(share %>% select(key, share, share_exporter), by = "key")
hosts_sf <- host_states %>% filter(key %in% HOST)
HOST_TOTAL <- sum(share$share_exporter[share$host])
LAB_SIZE <- 4.2
FIG_W <- 11; FIG_H <- 6.38
XLIM <- c(-2370e3, 2650e3); YLIM <- c(-1340e3, 1570e3)
M_PER_IN <- diff(YLIM) / (FIG_H - 8 / 72.27)
pts <- suppressWarnings(st_coordinates(st_point_on_surface(host_states)))
lab <- data.frame(ab = host_states$STUSPS, x = pts[, 1], y = pts[, 2], key = host_states$key,
                  v = ifelse(is.na(host_states$share_exporter), 0, host_states$share_exporter)) %>%
  mutate(txt = sprintf("%.1f%%", v), host = key %in% HOST, ca = ab == "CA")
callout <- data.frame(ab = c("VT", "NH", "MA", "RI", "CT", "NJ", "DE", "MD"),
                      lx = c(1590, 2200, 2300, 2300, 2300, 2100, 2100, 2100),
                      ly = c(1390, 890, 800, 705, 610, 480, 370, 260))
callout <- callout %>% left_join(lab %>% select(ab, x, y, txt), by = "ab") %>%
  mutate(lx = lx * 1e3, ly = ly * 1e3, tt = paste(ab, txt))
inner <- lab %>% filter(!ab %in% callout$ab)

ragg::agg_png(tempfile(fileext = ".png"), width = FIG_W, height = FIG_H, units = "in", res = 300)
text_size <- function(txt, bold = FALSE) {
  g <- grid::textGrob(txt, gp = grid::gpar(fontsize = LAB_SIZE * .pt, fontface = if (bold) "bold" else "plain"))
  c(w = grid::convertWidth(grid::grobWidth(g), "in", TRUE), h = grid::convertHeight(grid::grobHeight(g), "in", TRUE)) * M_PER_IN
}
inner <- cbind(inner, t(mapply(text_size, inner$txt, inner$host, USE.NAMES = FALSE)))
callout <- cbind(callout, t(mapply(text_size, callout$tt, USE.NAMES = FALSE)))
invisible(dev.off())

host_bd <- st_union(st_boundary(st_geometry(hosts_sf)))
HOST_HALF <- 1.5 * .pt / 72.27 / 2 * M_PER_IN
rects <- function(x, y, w, h) {
  st_sfc(lapply(seq_along(x), function(k) {
    st_polygon(list(rbind(c(x[k] - w / 2, y[k] - h / 2), c(x[k] + w / 2, y[k] - h / 2), c(x[k] + w / 2, y[k] + h / 2),
                          c(x[k] - w / 2, y[k] + h / 2), c(x[k] - w / 2, y[k] - h / 2))))
  }), crs = st_crs(host_states))
}
clearance <- function(poly, r) {
  pmin(as.numeric(st_distance(r, st_boundary(poly))), as.numeric(st_distance(r, host_bd)) - HOST_HALF)
}
best_spot <- function(poly, w, h, near = NULL) {
  scan <- function(xs, ys) {
    g <- expand.grid(x = xs, y = ys)
    g <- g[lengths(st_within(rects(g$x, g$y, w, h), poly)) > 0, ]
    g$clear <- clearance(poly, rects(g$x, g$y, w, h))
    g
  }
  bb <- st_bbox(poly)
  ctr <- if (is.null(near)) st_coordinates(st_centroid(poly)) else near * 1e3
  g <- scan(seq(bb["xmin"], bb["xmax"], 8e3), seq(bb["ymin"], bb["ymax"], 8e3))
  g <- g[g$clear >= 0.9 * max(g$clear), ]
  s <- g[which.min((g$x - ctr[1])^2 + (g$y - ctr[2])^2), ]
  g <- scan(s$x + seq(-8e3, 8e3, 2e3), s$y + seq(-8e3, 8e3, 2e3))
  unlist(g[which.max(g$clear), c("x", "y", "clear")])
}
NEAR <- list(FL = c(1451, -1018))
inner[c("x", "y", "clear")] <- t(sapply(seq_len(nrow(inner)), function(i) {
  best_spot(st_geometry(host_states)[host_states$STUSPS == inner$ab[i]], inner$w[i], inner$h[i], NEAR[[inner$ab[i]]])
}))
SHIFT <- list(FL = 10, WV = 4)
for (s in names(SHIFT)) {
  i <- which(inner$ab == s)
  inner$x[i] <- inner$x[i] + SHIFT[[s]] * 1e3
}
callout <- callout %>% mutate(ex = ifelse(ab == "VT", lx + w / 2, lx - 15e3), ey = ifelse(ab == "VT", ly - h / 2 - 12e3, ly))
BOX <- c(xmin = -2340, xmax = -1190, ymin = -1300, ymax = -900) * 1e3
host_map <- ggplot() +
  geom_sf(data = host_states, aes(fill = share_exporter), color = "grey40", linewidth = 0.3) +
  scale_fill_gradientn(colours = c("#deebf7", "#c6dbef", "#9ecae1", "#6baed6", "#4292c6",
                                   "#2171b5", "#08519c", "#08306b"),
                       trans = "sqrt", limits = c(0, ceiling(max(host_states$share_exporter, na.rm = TRUE))),
                       na.value = "grey85", guide = "none") +
  geom_sf(data = us_outline, fill = NA, color = "black", linewidth = 0.4) +
  geom_sf(data = hosts_sf, fill = NA, color = "black", linewidth = 1.5) +
  geom_segment(data = callout, aes(x = x, y = y, xend = ex, yend = ey), linewidth = 0.3, color = "grey25") +
  geom_text(data = inner %>% filter(!host, !ca), aes(x, y, label = txt), size = LAB_SIZE) +
  geom_text(data = inner %>% filter(host), aes(x, y, label = txt), size = LAB_SIZE, fontface = "bold") +
  geom_text(data = inner %>% filter(ca), aes(x, y, label = txt), size = LAB_SIZE, color = "white") +
  geom_text(data = callout, aes(lx, ly, label = tt), size = LAB_SIZE, hjust = 0) +
  annotate("rect", xmin = BOX["xmin"], xmax = BOX["xmax"], ymin = BOX["ymin"], ymax = BOX["ymax"],
           fill = "white", color = "black", linewidth = 1.0) +
  annotate("text", x = mean(BOX[1:2]), y = BOX["ymax"] - 72e3, label = "Four host states combined", size = 4.6) +
  annotate("text", x = mean(BOX[1:2]), y = mean(BOX[3:4]) - 5e3, label = sprintf("%.1f%%", HOST_TOTAL),
           size = 7.2, fontface = "bold") +
  annotate("text", x = mean(BOX[1:2]), y = BOX["ymin"] + 72e3, label = "(AZ, CO, KS, TX; thick borders)", size = 4.0) +
  coord_sf(datum = NA, xlim = XLIM, ylim = YLIM, expand = FALSE) +
  theme_void() +
  theme(plot.margin = margin(4, 4, 4, 4))
ggsave(file.path(out_dir, "new_feasible_trade_share_hosts_exporter_labeled.png"), host_map,
       width = FIG_W, height = FIG_H, dpi = 300, bg = "white")


.ceil_nice <- function(x) {
  if (!is.finite(x) || x <= 0) return(0)
  p <- 10^floor(log10(x)); m <- x / p
  cand <- c(1, 1.1, 1.2, 1.25, 1.3, 1.4, 1.5, 1.6, 1.75, 2, 2.25, 2.5,
            3, 3.5, 4, 4.5, 5, 6, 7, 7.5, 8, 9, 10)
  p * cand[which(cand >= m - 1e-9)][1]
}
.floor_nice <- function(x) if (!is.finite(x) || x >= 0) 0 else -.ceil_nice(-x)
.thin_breaks <- function(cand, lo, hi, budget = 60) {
  span <- hi - lo
  if (!is.finite(span) || span <= 0) return(sort(unique(cand)))
  w <- max(nchar(format(c(lo, hi), big.mark = ",", trim = TRUE, scientific = FALSE)))
  min_gap <- max(0.08, (w + 1) / budget)
  cand <- sort(unique(c(cand, lo, hi, if (lo < 0 && hi > 0) 0 else NULL, pretty(c(lo, hi), n = 7))))
  cand <- cand[cand >= lo - 1e-9 & cand <= hi + 1e-9]
  prio <- c(if (lo < 0 && hi > 0) 0 else NULL, hi, lo)
  keep <- numeric(0)
  for (b in c(prio, cand)) {
    if (length(keep) && min(abs(keep - b)) / span < min_gap) next
    keep <- c(keep, b)
  }
  sort(unique(keep))
}
.expand_one <- function(cfg, lo, hi) {
  nlo <- min(cfg$color_from[1], .floor_nice(lo))
  nhi <- max(cfg$color_from[2], .ceil_nice(hi))
  llo <- min(cfg$legend_lim[1], .floor_nice(lo))
  lhi <- max(cfg$legend_lim[2], .ceil_nice(hi))
  if (llo < cfg$legend_lim[1] || lhi > cfg$legend_lim[2]) cfg$breaks <- .thin_breaks(cfg$breaks, llo, lhi)
  cfg$breaks <- sort(unique(cfg$breaks))
  cfg$breaks <- cfg$breaks[cfg$breaks >= llo & cfg$breaks <= lhi]
  cfg$color_from <- c(nlo, nhi); cfg$legend_lim <- c(llo, lhi)
  cfg
}
expand_cfg_nested <- function(cfg, data_list, metrics, blocks) {
  for (b in names(blocks)) for (m in metrics) {
    v <- unlist(lapply(blocks[[b]], function(s) data_list[[s]][[m]]))
    cfg[[b]][[m]] <- .expand_one(cfg[[b]][[m]], min(v, na.rm = TRUE), max(v, na.rm = TRUE))
  }
  cfg
}

us_map <- map_data("state")
iso_to_state <- function(x) tolower(gsub("_", " ", x))
block_of <- function(s) if (s %in% scenarios_ndr) "ndr" else "dr"
make_rescaler <- function(from, expo_pos, expo_neg) {
  function(x, to = c(0, 1), from = from) {
    neg_max <- abs(from[1]); pos_max <- from[2]
    xt <- ifelse(x >= 0, (x / pos_max)^expo_pos, -(abs(x) / neg_max)^expo_neg)
    scales::rescale(xt, to = to, from = c(-1, 1))
  }
}

build_figure <- function(all_data, cfg_set, metrics, unit_name, label_fun = waiver(), xr = NULL, yr = NULL,
                         leg_title = 9, leg_text = 8, key_w = 1.9, key_h = 0.25,
                         row_lab = 10, gap = 2, leg_h = 0.22, lab_w = 0.075, wrap = FALSE, gap_out = 2) {
  unit_of <- function(m) if (!is.null(names(unit_name))) unname(unit_name[m]) else unit_name
  labels_of <- function(m) if (is.list(label_fun) && !inherits(label_fun, "waiver")) label_fun[[m]] else label_fun
  make_panel <- function(s, m, col = 1, ncol = 1) {
    cfg <- cfg_set[[block_of(s)]][[m]]
    rescaler <- make_rescaler(cfg$color_from, cfg$exp_pos, cfg$exp_neg)
    map_df <- us_map %>% left_join(all_data[[s]] %>% select(region, value = all_of(m)), by = "region")
    p <- ggplot(map_df, aes(x = long, y = lat, group = group, fill = value)) +
      geom_polygon(color = "grey30", linewidth = 0.3) +
      scale_fill_gradientn(colours = c("#d73027", "white", cfg$high), limits = cfg$color_from,
                           rescaler = rescaler, name = unit_of(m), na.value = "grey80")
    if (is.null(xr)) p <- p + coord_fixed(1.3)
    else p <- p + coord_fixed(1.3, xlim = xr, ylim = yr, expand = FALSE)
    ml <- if (col > 1) gap else gap_out; mr <- if (col < ncol) gap else gap_out
    p + theme_void(base_size = 10) + theme(legend.position = "none", plot.margin = margin(2, mr, 2, ml))
  }
  make_legend <- function(blk, m) {
    cfg <- cfg_set[[blk]][[m]]
    rescaler <- make_rescaler(cfg$color_from, cfg$exp_pos, cfg$exp_neg)
    pal <- scales::gradient_n_pal(c("#d73027", "white", cfg$high))
    lo <- cfg$legend_lim[1]; hi <- cfg$legend_lim[2]
    p <- ggplot(us_map %>% left_join(all_data[[scenarios[1]]] %>% select(region, value = all_of(m)), by = "region"),
                aes(x = long, y = lat, group = group, fill = value)) +
      geom_polygon() +
      scale_fill_gradientn(
        colours = c(pal(rescaler(lo, from = cfg$color_from)), pal(rescaler(0, from = cfg$color_from)),
                    pal(rescaler(hi, from = cfg$color_from))),
        values = c(0, (0 - lo) / (hi - lo), 1), limits = cfg$legend_lim, breaks = cfg$breaks, labels = labels_of(m),
        name = unit_of(m), na.value = "grey80") +
      theme(legend.position = "bottom", legend.title.position = "left",
            legend.key.width = unit(key_w, "cm"), legend.key.height = unit(key_h, "cm"),
            legend.title = element_text(size = leg_title, vjust = 1), legend.text = element_text(size = leg_text))
    get_legend(p)
  }
  block_body <- function(sufs, labs) {
    panels <- list()
    for (s in sufs) for (m in metrics) panels[[length(panels) + 1]] <- make_panel(s, m, match(m, metrics), length(metrics))
    grid <- wrap_plots(panels, nrow = length(sufs), ncol = length(metrics), byrow = TRUE)
    if (wrap) labs <- sub("(Existing Charging|Population-Center|Strategic Network) ", "\\1\n", labs)
    rows <- plot_grid(plotlist = lapply(labs, function(s)
      ggdraw() + draw_label(s, fontface = "bold", size = row_lab, angle = 90, lineheight = 0.95)), ncol = 1)
    plot_grid(rows, grid, nrow = 1, rel_widths = c(lab_w, 1))
  }
  legend_row <- function(blk) {
    nm <- length(metrics)
    lg <- plot_grid(plotlist = lapply(seq_along(metrics), function(k) {
      if (gap <= 2 && gap_out <= 2) return(make_legend(blk, metrics[k]))
      ml <- if (k > 1) gap else gap_out; mr <- if (k < nm) gap else gap_out
      plot_grid(make_legend(blk, metrics[k])) + theme(plot.margin = margin(0, mr, 0, ml))
    }), nrow = 1, ncol = nm)
    plot_grid(ggdraw(), lg, nrow = 1, rel_widths = c(lab_w, 1))
  }
  plot_grid(block_body(scenarios_dr, labels_dr), legend_row("dr"),
            block_body(scenarios_ndr, labels_ndr), legend_row("ndr"),
            ncol = 1, rel_heights = c(3, leg_h, 1, leg_h))
}

col_head <- function(size, x2) {
  ggdraw() +
    draw_label("(a)", x = x2[1], y = 0.5, fontface = "bold", size = size) +
    draw_label("(b)", x = x2[2], y = 0.5, fontface = "bold", size = size)
}

lab_nozero <- function(x) sub("\\.?0+$", "", formatC(x, format = "f", digits = 2))
h_4x2 <- 12.8
.s <- (h_4x2 / 12.6) * (0.74 / 0.78)
head_4x2 <- 19
style_4x2 <- list(leg_title = 16 * .s, leg_text = 15 * .s, key_w = 2.0, key_h = 0.45 * .s, row_lab = 15, gap = 36,
                  leg_h = 0.34, lab_w = 0.085, wrap = TRUE, gap_out = 8)
x2_4x2 <- local({ w <- style_4x2$lab_w / (1 + style_4x2$lab_w); d <- (style_4x2$gap - style_4x2$gap_out) / 2 / 72 / 11
                  c(w + (1 - w) / 4 - d, w + 3 * (1 - w) / 4 + d) })

all_data_pct <- list()
all_data_usd <- list()
all_data_welf <- list()
for (s in scenarios) {
  r <- results %>% filter(scenario == s) %>% mutate(region = iso_to_state(state))
  all_data_pct[[s]] <- r %>% select(region, Exports = exports_pct, Imports = imports_pct, Welfare = welfare_pct)
  all_data_usd[[s]] <- r %>% select(region, Exports = exports_diff, Imports = imports_diff)
  all_data_welf[[s]] <- r %>% select(region, Welfare = welfare_pct, WelfareUSD = welfare_diff)
}

cfg_pct <- list(
  dr = list(
    Exports = list(color_from = c(-1, 3), legend_lim = c(-1, 3), breaks = c(-1, -0.5, 0, 0.5, 1, 1.5, 2, 2.5, 3),
                   exp_pos = 1/1.3, exp_neg = 1/1.3, high = "#2166ac"),
    Imports = list(color_from = c(-1, 3), legend_lim = c(-1, 3), breaks = c(-1, -0.5, 0, 0.5, 1, 1.5, 2, 2.5, 3),
                   exp_pos = 1/1.3, exp_neg = 1/1.3, high = "#008837"),
    Welfare = list(color_from = c(-0.2, 0.8), legend_lim = c(-0.2, 0.8), breaks = c(-0.2, -0.1, 0, 0.2, 0.4, 0.6, 0.8),
                   exp_pos = 1/1.3, exp_neg = 1/1.3, high = "#f5c542")),
  ndr = list(
    Exports = list(color_from = c(-5, 40), legend_lim = c(-5, 40), breaks = c(-5, 0, 5, 10, 20, 30, 40),
                   exp_pos = 1/1.5, exp_neg = 1/1.5, high = "#2166ac"),
    Imports = list(color_from = c(-5, 30), legend_lim = c(-5, 30), breaks = c(-5, 0, 5, 10, 20, 30),
                   exp_pos = 1/1.5, exp_neg = 1/1.5, high = "#008837"),
    Welfare = list(color_from = c(-1, 8), legend_lim = c(-1, 8), breaks = c(-1, 0, 2, 4, 6, 8),
                   exp_pos = 1/1.5, exp_neg = 1/1.5, high = "#f5c542"))
)
cfg_pct <- expand_cfg_nested(cfg_pct, all_data_pct, c("Exports", "Imports", "Welfare"),
                             list(dr = scenarios_dr, ndr = scenarios_ndr))

inc_pairs <- list(
  a = c("real", "pop", "(a) Existing \u2192 Population-Center Expansion"),
  b = c("pop", "str", "(b) Population-Center \u2192 Strategic Expansion"),
  c = c("str", "auto", "(c) Strategic Expansion \u2192 Strategic + Autonomy\n(expanded scale)"))
inc_data <- lapply(inc_pairs, function(p) {
  a0 <- all_data_pct[[p[1]]] %>% select(region, w0 = Welfare)
  a1 <- all_data_pct[[p[2]]] %>% select(region, w1 = Welfare)
  inner_join(a0, a1, by = "region") %>% transmute(region, value = w1 - w0)
})
weights <- trade %>%
  group_by(destination) %>%
  summarise(w = sum(trade), .groups = "drop") %>%
  mutate(region = iso_to_state(destination), w = w / sum(w)) %>%
  select(region, w)
nat_welfare <- round(sapply(scenarios, function(s)
  sum(all_data_pct[[s]] %>% inner_join(weights, by = "region") %>% summarise(v = sum(Welfare * w)) %>% pull(v))), 3)
inc_nat <- sapply(inc_pairs, function(p) unname(nat_welfare[p[2]] - nat_welfare[p[1]]))
inc_note <- sprintf("National welfare: %+.3f pp", inc_nat)
names(inc_note) <- names(inc_pairs)

inc_panel <- function(df, cfg, title, note) {
  rescaler <- make_rescaler(cfg$color_from, cfg$exp_pos, cfg$exp_neg)
  map_df <- us_map %>% left_join(df, by = "region")
  p <- ggplot(map_df, aes(x = long, y = lat, group = group, fill = value)) +
    geom_polygon(color = "grey30", linewidth = 0.3) +
    scale_fill_gradientn(colours = c("#d73027", "white", cfg$high), limits = cfg$color_from,
                         rescaler = rescaler, na.value = "grey80") +
    coord_fixed(1.3) + theme_void(base_size = 16) +
    theme(legend.position = "none", plot.margin = margin(2, 2, 2, 2))
  head <- plot_grid(ggdraw() + draw_label(title, fontface = "bold", size = 16, lineheight = 0.9),
                    ggdraw() + draw_label(note, size = 15), ncol = 1, rel_heights = c(2.2, 1.0))
  plot_grid(head, p, ncol = 1, rel_heights = c(0.30, 1))
}
inc_legend <- function(cfg, title, keyw = 2.2) {
  rescaler <- make_rescaler(cfg$color_from, cfg$exp_pos, cfg$exp_neg)
  pal <- scales::gradient_n_pal(c("#d73027", "white", cfg$high))
  lo <- cfg$legend_lim[1]; hi <- cfg$legend_lim[2]
  vs <- seq(lo, hi, length.out = 61)
  cols <- pal(sapply(vs, function(v) rescaler(v, from = cfg$color_from)))
  dummy <- data.frame(x = c(lo, hi), y = c(1, 1), value = c(lo, hi))
  p <- ggplot(dummy, aes(x = x, y = y, fill = value)) + geom_tile() +
    scale_fill_gradientn(colours = cols, values = (vs - lo) / (hi - lo), limits = cfg$legend_lim,
                         breaks = cfg$breaks, name = title) +
    theme(legend.position = "bottom", legend.title.position = "top",
          legend.key.width = unit(keyw, "cm"), legend.key.height = unit(0.32, "cm"),
          legend.title = element_text(size = 15, hjust = 0.5), legend.text = element_text(size = 14))
  get_legend(p)
}
ab_v <- c(inc_data$a$value, inc_data$b$value)
hi_ab <- ceiling(max(ab_v) * 10) / 10
lo_c <- floor(min(inc_data$c$value) * 10) / 10; hi_c <- ceiling(max(inc_data$c$value))
cfg_ab <- list(color_from = c(lo_c, hi_ab), legend_lim = c(lo_c, hi_ab), breaks = unique(c(lo_c, 0, 0.5, 1, hi_ab)),
               exp_pos = 1/1.3, exp_neg = 1/1.5, high = "#f5c542")
cfg_c <- list(color_from = c(lo_c, hi_c), legend_lim = c(lo_c, hi_c), breaks = unique(c(0, 2, 4, 6, 8, hi_c)),
              exp_pos = 1/1.5, exp_neg = 1/1.5, high = "#f5c542")
pan_split <- list(inc_panel(inc_data$a, cfg_ab, inc_pairs$a[3], inc_note[["a"]]),
                  inc_panel(inc_data$b, cfg_ab, inc_pairs$b[3], inc_note[["b"]]),
                  inc_panel(inc_data$c, cfg_c, inc_pairs$c[3], inc_note[["c"]]))
leg_stack <- plot_grid(ggdraw(), inc_legend(cfg_ab, "Panels (a)-(b): change in welfare (pp)", keyw = 1.9),
                       inc_legend(cfg_c, "Panel (c): change in welfare (pp)", keyw = 1.9), ggdraw(),
                       ncol = 1, rel_heights = c(0.6, 1, 1, 0.6))
welfare_increments <- plot_grid(pan_split[[1]], pan_split[[2]], pan_split[[3]], leg_stack, nrow = 2, ncol = 2)
ggsave(file.path(out_dir, "combined_results_maps_welfare_inc_2x2.png"), welfare_increments,
       width = 11, height = 7.4, dpi = 150, bg = "white")

xr <- range(us_map$long); yr <- range(us_map$lat)
fig_pct <- do.call(build_figure, c(list(all_data_pct, cfg_pct, c("Exports", "Imports"), "%",
                                       label_fun = lab_nozero, xr = xr, yr = yr), style_4x2))
ggsave(file.path(out_dir, "combined_results_maps_perc.png"),
       plot_grid(col_head(head_4x2, x2_4x2), fig_pct, ncol = 1, rel_heights = c(0.03, 1)),
       width = 11, height = h_4x2, dpi = 150, bg = "white")

cfg_usd <- list(
  dr = list(
    Exports = list(color_from = c(-500, 7100), legend_lim = c(-500, 7000), breaks = c(0, 1000, 2000, 4000, 7000),
                   exp_pos = 1/1.5, exp_neg = 1/1.5, high = "#2166ac"),
    Imports = list(color_from = c(-500, 8500), legend_lim = c(-500, 8500), breaks = c(0, 1000, 2000, 4000, 8500),
                   exp_pos = 1/1.5, exp_neg = 1/1.5, high = "#008837")),
  ndr = list(
    Exports = list(color_from = c(-1100, 98000), legend_lim = c(-1000, 98000), breaks = c(0, 10000, 25000, 50000, 98000),
                   exp_pos = 1/1.5, exp_neg = 1/1.5, high = "#2166ac"),
    Imports = list(color_from = c(-1100, 108000), legend_lim = c(-1000, 108000), breaks = c(0, 10000, 25000, 50000, 108000),
                   exp_pos = 1/1.5, exp_neg = 1/1.5, high = "#008837"))
)
cfg_usd <- expand_cfg_nested(cfg_usd, all_data_usd, c("Exports", "Imports"), list(dr = scenarios_dr, ndr = scenarios_ndr))
for (b in names(cfg_usd)) for (m in names(cfg_usd[[b]])) {
  lim <- cfg_usd[[b]][[m]]$legend_lim
  br <- pretty(lim, n = 4)
  cfg_usd[[b]][[m]]$breaks <- br[br >= lim[1] & br <= lim[2] - 0.05 * diff(lim)]
}
fig_usd <- do.call(build_figure, c(list(all_data_usd, cfg_usd, c("Exports", "Imports"), "$",
                                       label_fun = scales::comma, xr = xr, yr = yr), style_4x2))
ggsave(file.path(out_dir, "combined_results_maps_dollar.png"),
       plot_grid(col_head(head_4x2, x2_4x2), fig_usd, ncol = 1, rel_heights = c(0.03, 1)),
       width = 11, height = h_4x2, dpi = 150, bg = "white")

cfg_welf <- list(
  dr = list(Welfare = cfg_pct$dr$Welfare,
            WelfareUSD = list(color_from = c(-500, 8000), legend_lim = c(-500, 8000), breaks = NULL,
                              exp_pos = 1/1.5, exp_neg = 1/1.5, high = cfg_pct$dr$Welfare$high)),
  ndr = list(Welfare = cfg_pct$ndr$Welfare,
             WelfareUSD = list(color_from = c(-1000, 45000), legend_lim = c(-1000, 45000), breaks = NULL,
                               exp_pos = 1/1.5, exp_neg = 1/1.5, high = cfg_pct$ndr$Welfare$high))
)
cfg_welf <- expand_cfg_nested(cfg_welf, all_data_welf, c("WelfareUSD"), list(dr = scenarios_dr, ndr = scenarios_ndr))
for (b in names(cfg_welf)) {
  lim <- cfg_welf[[b]]$WelfareUSD$legend_lim
  br <- pretty(lim, n = 4)
  cfg_welf[[b]]$WelfareUSD$breaks <- br[br >= lim[1] & br <= lim[2] - 0.05 * diff(lim)]
}
fig_welfare <- do.call(build_figure, c(list(all_data_welf, cfg_welf, c("Welfare", "WelfareUSD"), c(Welfare = "%", WelfareUSD = "$"),
                                           label_fun = list(Welfare = lab_nozero, WelfareUSD = scales::comma),
                                           xr = xr, yr = yr), style_4x2))
ggsave(file.path(out_dir, "combined_results_maps_welfare_4x2.png"),
       plot_grid(col_head(head_4x2, x2_4x2), fig_welfare, ncol = 1, rel_heights = c(0.03, 1)),
       width = 11, height = h_4x2, dpi = 150, bg = "white")
