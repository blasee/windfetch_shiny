options(shiny.maxRequestSize = 50 * 1024^2)

shinyServer(function(input, output) {
    
    rvs = reactiveValues(show_button = FALSE)
    
    observe({
        rvs$show_button = all(
            !is.null(input$polygon_shape),
            !is.null(input$point_shape),
            !is.null(input$n_dirs),
            !is.null(input$dist)
        )
    }
    )
    
    observeEvent(input$n_dirs,
                 {
                     if (all(!is.null(input$polygon_shape),
                             !is.null(input$point_shape))){
                         enable("submit")
                         rvs$show_button = TRUE
                     }
                 })
    
    observeEvent(rvs$show_button,
                 {
                     if (rvs$show_button)
                         enable("submit")
                     else
                         disable("submit")
                 })
    
    observeEvent(input$submit,
                 {
                     disable("submit")
                     calc_fetch()
                     rvs$show_button = FALSE
                 })
    
    polyShapeInput = reactive({
        inFile <- input$polygon_shape
        
        if (is.null(inFile))
            return(NULL)
        
        validate(need(any(grepl("\\.shp$", inFile$name)),
                      "Please include a shape format file (.shp)."))
        
        validate(need(any(grepl("\\.prj$", inFile$name)),
                      "Please include a projection format file (.prj)."))
        
        validate(need(any(grepl("\\.shx$", inFile$name)),
                      "Please include a shape index format file (.shx)."))
        
        # Names of the uploaded files
        infiles = inFile$datapath
        
        # Directory containing the files
        dir_name = unique(dirname(inFile$datapath))
        
        # New names for the files (matching the input names)
        outfiles = file.path(dir_name, inFile$name)
        walk2(infiles, outfiles, ~file.rename(.x, .y))
        
        x <- try(st_read(dir_name, strsplit(inFile$name[1], "\\.")[[1]][1]), TRUE)
        
        validate(need(class(x) != "try-error", "Could not read shapefile."))
        
        validate(need(!st_is_longlat(x),
                      "Please project the shapefile onto a suitable map projection."))
        list(x = x,
             dir_name = tail(strsplit(dir_name, "/")[[1]], 1))
    })
    
    pointShapeInput = reactive({
        inFile <- input$point_shape
        
        if (is.null(inFile))
            return(NULL)
        
        validate(need(any(grepl("\\.shp$", inFile$name)),
                      "Require a shape format (.shp)."))
        
        validate(need(any(grepl("\\.prj$", inFile$name)),
                      "Require a projection format (.prj)."))
        
        validate(need(any(grepl("\\.shx$", inFile$name)),
                      "Require a shape index format (.shx)."))
        
        # Names of the uploaded files
        infiles = inFile$datapath
        
        # Directory containing the files
        dir_name = unique(dirname(inFile$datapath))
        
        # New names for the files (matching the input names)
        outfiles = file.path(dir_name, inFile$name)
        walk2(infiles, outfiles, ~file.rename(.x, .y))
        
        x <- try(st_read(dir_name, strsplit(inFile$name[1], "\\.")[[1]][1]), TRUE)
        
        validate(need(class(x) != "try-error", "Could not read shapefile."))
        
        # validate(need(is(x, "SpatialPoints"),
        #               "Please provide a '[Multi]Point' shapefile."))
        
        # validate(need(length(x) < 101,
        #               "Please provide up to 100 sites to calculate."))
        list(x = x,
             dir_name = tail(strsplit(dir_name, "/")[[1]], 1))
    })
    
    output$polygon_map <- renderPlot({
        
        poly_layer = polyShapeInput()$x
        point_layer = pointShapeInput()$x
        
        if (is.null(input$polygon_shape) &
            input$submit == 0)
            return(NULL)
        
        if (is.null(input$point_shape)){
            
            plot(poly_layer$geometry, col = "lightgrey", border = "grey")
            
        } else {
            
            # If both projected, test for the same map projections here...
            
            if (all(!st_is_longlat(poly_layer),
                    st_is_longlat(point_layer)))
                point_layer = st_transform(point_layer, st_crs(poly_layer))
            
            validate(need(!any(lengths(st_overlaps(point_layer, poly_layer))),
                          "At least one site location is on land"))
            
            plot(point_layer$geometry, col = "red", pch = 4)
            plot(poly_layer$geometry, col = "lightgrey", border = "grey", add = TRUE)
            plot(point_layer$geometry, col = "red", pch = 4, add = TRUE)
        }
    })
    
    calc_fetch = eventReactive(input$submit, {
        
        poly_layer = polyShapeInput()$x
        point_layer = pointShapeInput()$x
        
        validate(need(all(input$n_dirs <= 90,
                          input$n_dirs > 0),
                      "Directions per quadrant: please choose a number between 1 and 90."))
        
        withProgress(message = "Calculating fetch", detail = "", value = 0, {
            
            if (any(grepl("^[Nn]ames{0,1}$", names(point_layer)))) {
                name_col = grep("^[Nn]ames{0,1}$", names(point_layer))
                site_names = as.character(data.frame(point_layer)[, name_col[[1]]])
            } else {
                site_names = paste("Site", seq_along(point_layer))
            }
            
            which_proj = c(!st_is_longlat(poly_layer), !st_is_longlat(point_layer))
            
            if (all(which_proj) && (st_crs(poly_layer) != st_crs(point_layer))) {
                point_layer = st_transform(point_layer, st_crs(poly_layer))
            }
            
            if (!which_proj[2]) {
                point_layer = st_transform(point_layer, st_crs(poly_layer))
            }
            
            max_dist = input$dist * 1000
            directions = head(seq(0, 360, by = 360 / (input$n_dirs * 4)), -1)
            dirs = as.numeric(directions)
            dirs_bin = findInterval(dirs, seq(45, 315, by = 90))
            quadrant = rep("North", length(dirs))
            quadrant[dirs_bin == 1] = "East"
            quadrant[dirs_bin == 2] = "South"
            quadrant[dirs_bin == 3] = "West"
            directions = unlist(split(directions, directions < 90), use.names = FALSE)
            
            fetch_ends = st_buffer(point_layer, max_dist, input$n_dirs)
            fetch_ends_df = as.data.frame(st_coordinates(fetch_ends))
            
            fetch_ends_df$site_names = site_names[fetch_ends_df[, 4]]
            
            fetch_locs_df = as.data.frame(st_coordinates(point_layer))
            colnames(fetch_locs_df) = c("X0", "Y0")
            fetch_locs_df$site_names = site_names
            
            fetch_df = unique(left_join(fetch_ends_df, fetch_locs_df, by = "site_names"))
            fetch_df$directions = c(head(seq(90, 360, by = 360 / (input$n_dirs * 4)), -1),
                                    head(seq(0, 90, by = 360 / (input$n_dirs * 4)), -1))
            fetch_df = fetch_df[with(fetch_df, order(site_names, directions)), ]
            
            
            fetch_df = st_sf(fetch_df[, c("site_names", "directions")],
                             geom = st_sfc(sapply(apply(fetch_df, 1, function(x) {
                                 X0 = as.numeric(x['X0'])
                                 Y0 = as.numeric(x['Y0'])
                                 X = as.numeric(x['X'])
                                 Y = as.numeric(x['Y'])
                                 st_sfc(st_linestring(matrix(c(X0, X, Y0, Y), 2, 2), dim = "XY"))
                             }), st_sfc), crs = st_crs(poly_layer)),
                             origin = st_sfc(sapply(apply(fetch_df, 1, function(x) {
                                 st_sfc(st_point(c(as.numeric(x['X0']), as.numeric(x['Y0']))))
                             }), st_sfc), crs = st_crs(poly_layer)))
            
            poly_subset = subset(poly_layer, 
                                 lengths(st_intersects(poly_layer, fetch_df)) > 0)
            
            inc = 1 / nrow(fetch_df)
            
            for (i in 1:nrow(fetch_df)) {
                fetch_df$fetch[i] = as.data.frame(
                    return_fetch_vector(fetch_df[i, "geom"],
                                        fetch_df$origin[i],
                                        poly_subset))
                incProgress(inc, "Calculating fetch ", 
                            paste0(fetch_df$site_names[i], " (", 
                                   round(i / nrow(fetch_df) * 100), "%)"))
            }
            
            setProgress(1)
            fetch_df$fetch = st_sfc(lapply(fetch_df$fetch, `[[`, 1),
                                    crs = st_crs(poly_layer))
            
            st_geometry(fetch_df) = fetch_df$fetch
            fetch_df = fetch_df[, 1:2]
            fetch_df$quadrant = factor(quadrant,
                                       levels = c("North", "East", 
                                                  "South", "West"))
            fetch_df$fetch = st_length(fetch_df$geom)
            
            my_fetch = new("WindFetch", fetch_df, names = site_names, 
                           max_dist = max_dist / 1000)
            
            list(my_fetch = my_fetch,
                 my_fetch_latlon = crs_transform(my_fetch, "epsg:4326"))
        })
        
        # withCallingHandlers({
        #   html("text", "")
        #   my_fetch = fetch(poly_layer,
        #                    point_layer,
        #                    max_dist = input$dist,
        #                    n_directions = input$n_dirs,
        #                    quiet = TRUE)
        #   message("")
        # },
        # message = function(m){
        #   emph_text = paste0("<strong>", m$message, "</strong>")
        #   html(id = "text", html = emph_text)
        # })
        
        
    })
    
    output$fetch_plot = renderPlot({
        plot(calc_fetch()$my_fetch)
        plot(polyShapeInput()$x$geometry, col = "lightgrey", 
             border = "grey", add = TRUE)
    })
    
    output$summary = renderTable({
        poly_layer = polyShapeInput()$x
        point_layer = pointShapeInput()$x
        
        if (is.null(input$polygon_shape) &
            input$submit == 0)
            return(NULL)
        
        summary(calc_fetch()$my_fetch)
    },
    rownames = TRUE, colnames = TRUE)
    
    output$distances = DT::renderDataTable({
        poly_layer = polyShapeInput()$x
        point_layer = pointShapeInput()$x
        
        if (is.null(input$polygon_shape) &
            input$submit == 0)
            return(NULL)
        
        calc_fetch.df = as(calc_fetch()$my_fetch_latlon, "data.frame")
        class(calc_fetch.df$direction) = "numeric"
        calc_fetch.df
    })
    
    output$dl_file = downloadHandler(
        filename = function(){
            paste0(strsplit(input$file_name, ".", fixed = TRUE)[[1]][1], ".zip")
            },
        content = function(file){
            fetch_obj = calc_fetch()$my_fetch_latlon
            setwd(tempdir())
            dir.create("CSV", showWarnings = FALSE)
            
            if (file.exists("CSV/fetch.csv"))
                file.remove("CSV/fetch.csv")
            write.csv(as(fetch_obj, "data.frame"), "CSV/fetch.csv")
            
            if (file.exists("CSV/fetch_summary.csv"))
                file.remove("CSV/fetch_summary.csv")
            write.csv(summary(fetch_obj), "CSV/fetch_summary.csv")
            
            dir.create("Shapefile", showWarnings = FALSE)
            st_write(as_sf(fetch_obj), dsn = "Shapefile", append = FALSE,
                     layer = strsplit(input$file_name, ".", fixed = TRUE)[[1]][1], 
                     driver = "ESRI Shapefile")
            
            zip(file, c(
                list.files("CSV/", full.names = TRUE),
                list.files("Shapefile/", full.names = TRUE)))
        },
        contentType = "application/zip"
    )
})