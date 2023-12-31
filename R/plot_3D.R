#' Create 3D interactive elevation map from gpx tracklogs
#'
#' @param tracklog_folder The path to the folder of your gpx file to be read by strava::process_data().
#' process_data() will read all gpx files from this folder and plot_3D() will plot them all.
#' It is however recommended to PLACE ONLY ONE GPX file within the folder.
#' If the tracks cover an extended area plot_3D() can slow down significantly.
#' If tracklog_folder is undefined plot_3D() loads an example tracklog provided with the package.
#' @param cache_folder Directory to store the downloaded elevation data and overlay image for reuse
#' @param elevation_scale Horizontal vs vertical ratio of the plot. Could be estimated with geoviz::raster_zscale(dem).
#' @param elevation_scale_tracklog_corr Raises elevation_scale for the tracklog by the specified percentage.
#' Useful if tracklog occasionally disappears into the ground.
#' @param buffer_around_tracklog_km Buffer distance around the tracklog in km. Scene is cut outside this.
#' @param render_high_quality If set to TRUE the function downloads higher resolution elevation and overlay data.
#' All steps are very time and resource consuming.
#' @param sunangle The direction of the light source of the scene
#' @param sunaltitude The angle, in degrees (as measured from the horizon) from which the light originates.
#' @param color_tracklog Color of the tracklog on the scene.
#' @param color_background Color of the scene's background.
#' @param water_detect If set to TRUE rayshader will look for flat surfaces in the scene and render them in blue
#'
#' @export
#' @import geoviz rayshader magick
#' @importFrom raster raster writeRaster extract extent
#'
#' @examples
#' \dontrun{
#' # Generate a built in demo by simply running
#' strava::plot_3D()
#' }
plot_3D <- function(
                     tracklog_folder = NULL,
                     cache_folder = "~/cache_plot_3D",
                     elevation_scale = 6, #
                     elevation_scale_tracklog_corr = .01,
                     buffer_around_tracklog_km = 1,
                     render_high_quality = FALSE,
                     sunangle = 250,
                     sunaltitude = 75,
                     color_tracklog = 'blue',
                     color_background = 'lightskyblue1',
                     water_detect = FALSE
                    ) {

  if (!file.exists(cache_folder)) dir.create(cache_folder)
  dem_file     <- paste0(cache_folder, "/dem"          ,if(render_high_quality) "_hq")
  overlay_file <- paste0(cache_folder, "/overlay_image",if(render_high_quality) "_hq", ".rds")


  message("Reading the tracklog")
  if (is.null(tracklog_folder)) {
    tracklog <- strava::process_data(system.file("gpx/mtb", package = "strava"))
  } else {
    tracklog <- strava::process_data(tracklog_folder)
  }



  if( paste0(dem_file,".gri") %>% file.exists() ) {

    message("Loading Digital Elevation Model (DEM) from disk")
    dem <- raster::raster(dem_file)

  } else {

    message("Downloading Digital Elevation Model (DEM)")
    dem <- geoviz::mapzen_dem(lat  = tracklog$lat,
                              long = tracklog$lon,
                              max_tiles = if(render_high_quality) 100 else 10)

    # Downloaded DEM tiles cover a larger area so we crop them to fit the tracklog
    message("Cropping DEM")
    dem <- geoviz::crop_raster_track(dem,
                                     lat  = tracklog$lat,
                                     long = tracklog$lon,
                                     width_buffer = buffer_around_tracklog_km)

    message("Saving DEM to disk")
    raster::writeRaster(x = dem, filename = dem_file, overwrite = TRUE)

  }


  message("Calculating elevation matrix")
  elmat <- matrix(
    raster::extract(dem, raster::extent(dem), method = 'bilinear'),
    nrow = ncol(dem),
    ncol = nrow(dem)
    )


  if( overlay_file %>% file.exists() ) {

    message("Loading overlay image from disk")
    overlay_image <- readRDS(overlay_file)

  } else {

    message("Downloading overlay image")
    overlay_image <- geoviz::slippy_overlay(
      dem,
      image_source = "stamen",
      image_type = "terrain",
      max_tiles = if(render_high_quality) 500 else 10,
      return_png = T,
      png_opacity = 0.5)
    saveRDS(overlay_image, overlay_file)
  }


  message("Calculating the scene")

  scene <- elmat %>%
    rayshader::sphere_shade(sunangle = sunangle) %>%
    { if (water_detect) rayshader::add_water(rayshader::detect_water(elmat), color = "lightblue") else . } %>%
    rayshader::add_shadow(rayshader::ray_shade(elmat,
                                               sunangle = sunangle,
                                               sunaltitude = sunaltitude,
                                               zscale = elevation_scale,
                                               multicore = FALSE),
                          max_darken = 0.2) %>%
    rayshader::add_shadow(rayshader::lamb_shade(elmat,zscale = elevation_scale, sunaltitude = 3),
                          max_darken = 0.5) %>%
    rayshader::add_overlay(overlay_image, alphalayer = .6)


  message("Plotting the scene")

  rayshader::plot_3d(
    scene,
    elmat,
    zscale = elevation_scale,
    #baseshape = 'circle',
    zoom = 0.8,
    fov = 10,
    mouseMode = c("none", "trackball", "zoom", "none", "zoom"),
    #windowsize = c(854,480),
    shadowcolor = 'grey10',
    background = color_background,
    triangulate = F
    )


  message("Adding tracklog to the scene")

  geoviz::add_gps_to_rayshader(
    dem,
    tracklog$lat,
    tracklog$lon,
    #tracklog$ele,
    clamp_to_ground = TRUE,
    line_width = 3,
    lightsaber = FALSE,
    alpha = .9,
    colour = color_tracklog,
    zscale = elevation_scale/(1+elevation_scale_tracklog_corr)
  )
}
