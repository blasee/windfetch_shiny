shinyUI(fluidPage(
  useShinyjs(),
  
  titlePanel("Calculate Wind Fetch"),
  br(),
  
  sidebarLayout(
    
    sidebarPanel(
      
      helpText("1) Upload a polygon shapefile. Each polygon represents a coastline boundary, island or other obstruction to wind."),
      fileInput('polygon_shape', 'Upload polygon shapefile',
                accept=c(".shp",".dbf",".sbn",".sbx",".shx",".prj"),
                multiple = TRUE, width = "100%"),
      
      helpText("2) Upload a points shapefile. Each point represents the location(s) at which the wind fetch will be calculated."),
      fileInput('point_shape', 'Upload points shapefile',
                accept=c(".shp",".dbf",".sbn",".sbx",".shx",".prj"),
                multiple = TRUE, width = "100%"),
      
      helpText("3) Set the maximum distance for all fetch vectors."),
      numericInput("dist",
                   label = "Maximum distance (km)",
                   value = 300,
                   min = 10,
                   max = 500,
                   step = 50,
                   width = '300px'),
      
      helpText("4) Set the number of directions to calculate per 90°"),
      numericInput("n_dirs",
                   label = "Directions per quadrant",
                   value = 9,
                   min = 1,
                   max = 20,
                   step = 1,
                   width = '300px'),
      br(),
      
      helpText("5) Calculate wind fetch!"),
      actionButton("submit", "Calculate fetch"),
      
      br(),
      br(),
      tags$div(class = "header", checked = NA,
               tags$p("Please don't forget to ",
                      tags$a("cite ", tags$strong("windfetch"), href = "https://github.com/blasee/windfetch#citation"),
                      "in publications.")
      ),
      
      textOutput("text"),
      
      conditionalPanel("input.submit > 0",
                       hr(),
                       helpText("Download the results."),
                       textInput("file_name", "Filename:", "my_fetch"),
                       downloadButton("dl_file", "Download")),
      
      width = 3
    ),
    
    mainPanel(
      tabsetPanel(
        tabPanel("Home",
                 plotOutput("polygon_map")
        ),
        tabPanel("Plot",
                 plotOutput("fetch_plot",
                            height = "800px")),
        tabPanel("Summary",
                 tableOutput("summary")),
        tabPanel("Distances",
                 dataTableOutput("distances")),
        tabPanel("Help",
                 includeMarkdown("README.md"))
      )
    )
  )
))
