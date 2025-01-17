@userplot ImPlot
@recipe function f(h::ImPlot)
    if length(h.args) != 1 || !(typeof(h.args[1]) <: AbstractArray)
        error("Image plots require an arugment that is a subtype of AbstractArray.  Got: $(typeof(h.args))")
    end
    data = only(h.args)
    if !(typeof(data) <: AstroImage)
        data = AstroImage(only(h.args))
    end
    T = eltype(data)
    if ndims(data) != 2
        error("Image passed to `implot` must be two-dimensional.  Got ndims(img)=$(ndims(data))")
    end

    wcsn = get(plotattributes, :wcsn, 1)
    # Show WCS coordinates if wcsticks is true or unspecified, and has at least one WCS axis present.
    showwcsticks = get(plotattributes, :wcsticks, true) &&  !all(==(""), wcs(data, wcsn).ctype)
    showwcstitle = get(plotattributes, :wcstitle, true) &&  length(refdims(data)) > 0 && !all(==(""), wcs(data, wcsn).ctype)

        
       
    minx = first(parent(dims(data,1)))
    maxx = last(parent(dims(data,1)))
    miny = first(parent(dims(data,2)))
    maxy = last(parent(dims(data,2)))
    extent = (minx-0.5, maxx+0.5, miny-0.5, maxy+0.5)
    if haskey(plotattributes, :xlims)
        extent = (plotattributes[:xlims]..., extent[3:4]...)
    end
    if haskey(plotattributes, :ylims)
        extent = (extent[1:2]..., plotattributes[:ylims]...)
    end
    if showwcsticks
        wcsg = WCSGrid(data, Float64.(extent), wcsn)
        gridspec = wcsgridspec(wcsg)
    end

    # Use package defaults if not user provided.
    clims   --> _default_clims[]
    stretch --> _default_stretch[]
    cmap    --> _default_cmap[]

    bias = get(plotattributes, :bias, 0.5)
    contrast = get(plotattributes, :contrast, 1)
    platescale = get(plotattributes, :platescale, 1)

    grid := false
    # In most cases, a grid framestyle is a nicer looking default for images
    # but the user can override.
    framestyle --> :box


    if T <: Colorant
        imgv = data
    else
        clims   = plotattributes[:clims]
        stretch = plotattributes[:stretch]
        cmap    = plotattributes[:cmap]
        if T <: Complex
            img = abs.(data)
            img["UNIT"] = "magnitude"
        else
            img = data
        end
        imgv = imview(img; clims, stretch, cmap, contrast, bias)
    end

    # Reduce large images using the same heuristic as Images.jl
    maxpixels = get(plotattributes, :maxpixels, 10^6)
    _length1(A::AbstractArray) = length(eachindex(A))
    _length1(A) = length(A)
    while _length1(imgv) > maxpixels
        imgv = restrict(imgv)
    end

    # We have to do a lot of flipping to keep the orientation corect 
    yflip := false
    xflip := false

    
    # Disable equal aspect ratios if the scales are totally different
    displayed_data_ratio = (extent[2]-extent[1])/(extent[4]-extent[3])
    if displayed_data_ratio >= 7
        aspect_ratio --> :none
    end


    # we have a wcs flag (from the image by default) so that users can skip over 
    # plotting in physical coordinates. This is especially important
    # if the WCS headers are mallformed in some way.
    showgrid = get(plotattributes, :xgrid, true) && get(plotattributes, :ygrid, true)
    # Display a title giving our position along unplotted dimensions
    if length(refdims(imgv)) > 0
        if showwcstitle
            refdimslabel = join(map(refdims(imgv)) do d
                # match dimension with the wcs axis number
                i = wcsax(imgv, d)
                ct = wcs(imgv, wcsn).ctype[i]
                label = ctype_label(ct, wcs(imgv, wcsn).radesys)
                if label == "NONE"
                    label = name(d)
                end
                value = pix_to_world(imgv, [1,1]; wcsn, all=true, parent=true)[i]
                unit = wcs(imgv, wcsn).cunit[i]
                if ct == "STOKES"
                    return _stokes_name(_stokes_symbol(value))
                else
                    return @sprintf("%s = %.5g %s", label, value, unit)
                end
            end, ", ")
        else
            refdimslabel = join(map(d->"$(name(d))= $(d[1])", refdims(imgv)), ", ")
        end
        title --> refdimslabel
    end

    # To ensure the physical axis tick labels are correct the axes must be
    # tight to the image
    xl = (first(dims(imgv,1))-0.5)*platescale, (last(dims(imgv,1))+0.5)*platescale
    yl = (first(dims(imgv,2))-0.5)*platescale, (last(dims(imgv,2))+0.5)*platescale
    ylims --> yl
    xlims --> xl

    subplot_i = 0
    # Actual image series (RGB pixels by this point)
    @series begin
        subplot_i += 1
        subplot := subplot_i
        colorbar := false
        aspect_ratio --> 1

        # Note: if the axes are on unusual sides (e.g. y-axis at right, x-axis at top)
        # then these coordinates are not correct. They are only correct exactly
        # along the axis.
        # In astropy, the ticks are actually tilted to reflect this, though in general
        # the transformation from pixel to coordinates can be non-linear and curved.
        
        if showwcsticks
            xticks --> (gridspec.tickpos1x, wcslabels(wcs(imgv, wcsn), wcsax(imgv, dims(imgv,1)), gridspec.tickpos1w))
            xguide --> ctype_label(wcs(imgv, wcsn).ctype[wcsax(imgv, dims(imgv,1))], wcs(imgv, wcsn).radesys)

            yticks --> (gridspec.tickpos2x, wcslabels(wcs(imgv, wcsn), wcsax(imgv, dims(imgv,2)), gridspec.tickpos2w))
            yguide --> ctype_label(wcs(imgv, wcsn).ctype[wcsax(imgv, dims(imgv,2))], wcs(imgv, wcsn).radesys)
        end

    
        ax1 = collect(parent(dims(imgv,1))) .* platescale
        ax2 = collect(parent(dims(imgv,2))) .* platescale
        # Views of images are not currently supported by plotly() so we have to collect them.
        # ax1, ax2, view(parent(imgv), reverse(axes(imgv,1)),:)
        ax1, ax2, parent(imgv)[reverse(axes(imgv,1)),:]
    end

    # If wcs=true (default) and grid=true (not default), overplot a WCS 
    # grid.
    if showgrid && showwcsticks

        # Plot the WCSGrid as a second series (actually just lines)
        @series begin
            subplot := 1
            # Use a default grid color that shows up across more 
            # color maps
            if !haskey(plotattributes, :xforeground_color_grid) && !haskey(plotattributes, :yforeground_color_grid)
                gridcolor --> :lightgray
            end

            wcsg, gridspec
        end
    end
    

    # Disable the colorbar.
    # Plots.jl does not give us sufficient control to make sure the range and ticks
    # are correct after applying a non-linear stretch.
    # We attempt to make our own colorbar using a second plot.
    showcolorbar = !(T <: Colorant) && get(plotattributes, :colorbar, true) != :none
    if T <: Complex
        layout := @layout [
            imgmag{0.5h}
          imgangle{0.5h}
        ]
    end
    if showcolorbar
        if T <: Complex
            layout := @layout [
                imgmag{0.95w, 0.5h}       colorbar{0.5h}
              imgangle{0.95w, 0.5h}  colorbarangle{0.5h}
            ]
        else
            layout := @layout [
                img{0.95w} colorbar
            ]
        end
        colorbar_title = get(plotattributes, :colorbar_title, "")
        if !haskey(plotattributes, :colorbar_title)
            if haskey(header(img), "UNIT")
                colorbar_title = string(img[:UNIT])
            elseif haskey(header(img), "BUNIT")
                colorbar_title = string(img[:BUNIT])
            end
        end

        subplot_i += 1
        @series begin
            subplot := subplot_i
            aspect_ratio := :none
            colorbar := false
            cbimg, cbticks = imview_colorbar(img; clims, stretch, cmap, contrast, bias)
            xticks := []
            ymirror := true
            yticks := cbticks
            yguide := colorbar_title
            xguide := ""
            xlims := Tuple(axes(cbimg, 2))
            ylims := Tuple(axes(cbimg, 2))
            title := ""
            # Views of images are not currently supported by plotly so we have to collect them
            # view(cbimg, reverse(axes(cbimg,1)),:)
            cbimg[reverse(axes(cbimg,1)),:]
        end    
    end


    # TODO: refactor to reduce duplication
    if T <: Complex
        img = angle.(data)
        img["UNIT"] = "angle (rad)"
        imgv = imview(img, clims=(-1pi, 1pi),stretch=identity, cmap=:cyclic_mygbm_30_95_c78_n256_s25)
        @series begin
            subplot_i += 1
            subplot := subplot_i
            colorbar := false
            title := ""
            aspect_ratio --> 1


            # Note: if the axes are on unusual sides (e.g. y-axis at right, x-axis at top)
            # then these coordinates are not correct. They are only correct exactly
            # along the axis.
            # In astropy, the ticks are actually tilted to reflect this, though in general
            # the transformation from pixel to coordinates can be non-linear and curved.
            
            if showwcsticks
                xticks --> (gridspec.tickpos1x, wcslabels(wcs(imgv, wcsn), wcsax(imgv, dims(imgv,1)), gridspec.tickpos1w))
                xguide --> ctype_label(wcs(imgv, wcsn).ctype[wcsax(imgv, dims(imgv,1))], wcs(imgv, wcsn).radesys)

                yticks --> (gridspec.tickpos2x, wcslabels(wcs(imgv, wcsn), wcsax(imgv, dims(imgv,2)), gridspec.tickpos2w))
                yguide --> ctype_label(wcs(imgv, wcsn).ctype[wcsax(imgv, dims(imgv,2))], wcs(imgv, wcsn).radesys)
            end
        
            ax1 = collect(parent(dims(imgv,1))) .* platescale
            ax2 = collect(parent(dims(imgv,2))) .* platescale
            # Views of images are not currently supported by plotly() so we have to collect them.
            # ax1, ax2, view(parent(imgv), reverse(axes(imgv,1)),:)
            ax1, ax2, parent(imgv)[reverse(axes(imgv,1)),:]
        end

        if showcolorbar
            colorbar_title = get(plotattributes, :colorbar_title, "")
            if !haskey(plotattributes, :colorbar_title) && haskey(header(img), "UNIT")
                colorbar_title = string(img[:UNIT])
            end
    

            @series begin
                subplot_i += 1
                subplot := subplot_i
                aspect_ratio := :none
                colorbar := false
                cbimg, _ = imview_colorbar(img; stretch=identity, clims=(-pi, pi), cmap=:cyclic_mygbm_30_95_c78_n256_s25)
                xticks := []
                ymirror := true
                ax = axes(cbimg,1)
                yticks := ([first(ax), mean(ax), last(ax)], ["-π", "0", "π"])
                yguide := colorbar_title
                xguide := ""
                xlims := Tuple(axes(cbimg, 2))
                ylims := Tuple(axes(cbimg, 2))
                title := ""
                view(cbimg, reverse(axes(cbimg,1)),:)
            end    
        end

    end


    return
end


"""
    implot(
        img::AbstractArray;
        clims=Percent(99.5),
        stretch=identity,
        cmap=:magma,
        bias=0.5,
        contrast=1,
        wcsticks=true,
        grid=true,
        platescale=1
    )

Create a read only view of an array or AstroImageMat mapping its data values
to an array of Colors. Equivalent to:

    implot(
        imview(
            img::AbstractArray;
            clims=Percent(99.5),
            stretch=identity,
            cmap=:magma,
            bias=0.5,
            contrast=1,
        ),
        wcsn=1,
        wcsticks=true,
        wcstitle=true,
        grid=true,
        platescale=1
    )

### Image Rendering
See `imview` for how data is mapped to RGBA pixel values.

### WCS & Image Coordinates
If provided with an AstroImage that has WCS headers set, the tick marks and plot grid
are calculated using WCS.jl. By default, use the first WCS coordinate system.
The underlying pixel coordinates are those returned by `dims(img)` multiplied by `platescale`.
This allows you to overplot lines, regions, etc. using pixel coordinates.
If you wish to compute the pixel coordinate of a point in world coordinates, see `world_to_pix`.

* `wcsn` (default `1`) select which WCS transform in the headers to use for ticks & grid
* `wcsticks` (default `true` if WCS headers present) display ticks and labels, and title using world coordinates
* `wcstitle` (default `true` if WCS headers present and `length(refdims(img))>0`). When slicing a cube, display the location along unseen axes in world coordinates instead of pixel coordinates.
* `grid` (default `true`) show a grid over the plot. Uses WCS coordinates if `wcsticks` is true, otherwise pixel coordinates multiplied by `platescale`.
* `platescale` (default `1`). Scales the underlying pixel coordinates to ease overplotting, etc. If `wcsticks` is false, the displayed pixel coordinates are also scaled.


### Defaults
The default values of `clims`, `stretch`, and `cmap` are `extrema`, `identity`, and `nothing`
respectively.
You may alter these defaults using `AstroImages.set_clims!`,  `AstroImages.set_stretch!`, and
`AstroImages.set_cmap!`.
"""
implot

struct WCSGrid
    img::AstroImage
    extent::NTuple{4,Float64}
    wcsn::Int
end


"""
    wcsticks(img, axnum)

Generate nice tick labels for an AstroImageMat along axis `axnum`
Returns a vector of pixel positions and a vector of strings.

Example:
plot(img, xticks=wcsticks(WCSGrid(img), 1), yticks=wcsticks(WCSGrid(img), 2))
"""
function wcsticks(wcsg::WCSGrid, axnum, gs = wcsgridspec(wcsg))
    tickposx = axnum == 1 ? gs.tickpos1x : gs.tickpos2x
    tickposw = axnum == 1 ? gs.tickpos1w : gs.tickpos2w
    return tickposx, wcslabels(
        wcs(wcsg.img, wcsg.wcsn),
        axnum,
        tickposw
    )
end

# Function to generate nice string coordinate labels given a WCSTransform, axis number,
# and a vector of tick positions in world coordinates.
# This is used for labelling ticks and for annotating grid lines.
function wcslabels(w::WCSTransform, axnum, tickposw)

    if length(tickposw) == 0
        return String[]
    end

    # Select a unit converter (e.g. 12.12 -> (a,b,c,d)) and list of units
    if w.cunit[axnum] == "deg"
        if startswith(uppercase(w.ctype[axnum]), "RA")
            converter = deg2hms
            units = hms_units
        else
            converter = deg2dmsmμ
            units = dmsmμ_units
        end
    else
        converter = x->(x,)
        units = ("",)
    end

    # Format inital ticklabel 
    ticklabels = fill("", length(tickposw))
    # We only include the part of the label that has changed since the last time.
    # Split up coordinates into e.g. sexagesimal
    parts = map(tickposw) do w
        vals = converter(w)
        return vals
    end

    # Start with something impossible of the same size:
    last_coord = Inf .* converter(first(tickposw))
    zero_coords_i = maximum(map(parts) do vals
        changing_coord_i = findfirst(vals .!= last_coord)
        if isnothing(changing_coord_i)
            changing_coord_i = 1
        end
        last_coord = vals
        return changing_coord_i
    end)


    # Loop through using only the relevant part of the label
    # Start with something impossible of the same size:
    last_coord = Inf .* converter(first(tickposw))
    for (i,vals) in enumerate(parts)
        changing_coord_i = findfirst(vals .!= last_coord)
        if isnothing(changing_coord_i)
            changing_coord_i = 1
        end
        # Don't display just e.g. 00" when we should display 50'00"
        if changing_coord_i > 1 && vals[changing_coord_i] == 0
            changing_coord_i = changing_coord_i -1
        end
        val_unit_zip = zip(vals[changing_coord_i:zero_coords_i],units[changing_coord_i:zero_coords_i])
        ticklabels[i] = mapreduce(*, enumerate(val_unit_zip)) do (coord_i,(val,unit))
            # If the last coordinate we print if the last coordinate we have available,
            # display it with decimal places
            if coord_i + changing_coord_i - 1== length(vals)
                str = @sprintf("%.2f", val)
            else
                str = @sprintf("%02d", val)
            end
            if length(str) > 0
                return str * unit
            else
                return str
            end
        end
        last_coord = vals
    end

    return ticklabels
end

# Extended form of deg2dms that further returns mas, microas.
function deg2dmsmμ(deg)
    d,m,s = deg2dms(deg)
    s_f = floor(s)
    mas = (s - s_f)*1e3
    mas_f = floor(mas)
    μas = (mas - mas_f)*1e3
    return (d,m,s_f,mas_f,μas)
end
const dmsmμ_units = [
    "°",
    "'",
    "\"",
    "mas",
    "μas",
]
const hms_units = [
    "ʰ",
    "ᵐ",
    "ˢ",
]

function ctype_label(ctype,radesys)
    if length(ctype) == 0
        return radesys
    elseif startswith(ctype, "RA")
        return "Right Ascension ($(radesys))"
    elseif startswith(ctype, "GLON")
        return "Galactic Longitude"
    elseif startswith(ctype, "TLON")
        return "ITRS"
    elseif startswith(ctype, "DEC")
        return "Declination ($(radesys))"
    elseif startswith(ctype, "GLAT")
        return "Galactic Latitude"
    # elseif startswith(ctype, "TLAT")
    elseif ctype == "STOKES"
        return "Polarization"
    else
        return ctype
    end
end



"""
    WCSGrid(img::AstroImageMat, ax=(1,2), coords=(first(axes(img,ax[1])),first(axes(img,ax[2]))))

Given an AstroImageMat, return information necessary to plot WCS gridlines in physical
coordinates against the image's pixel coordinates.
This function has to work on both plotted axes at once to handle rotation and general
curvature of the WCS grid projected on the image coordinates.

"""
function WCSGrid(img::AstroImageMat, wcsn=1)
    minx = first(dims(img,2))
    maxx = last(dims(img,2))
    miny = first(dims(img,1))
    maxy = last(dims(img,1))
    extent = (minx-0.5, maxx+0.5, miny-0.5, maxy+0.5)
    @show extent
    return WCSGrid(img, extent, wcsn)
end



# Recipe for a WCSGrid with lines, optional ticks (on by default),
# and optional grid labels (off by defaut).
# The AstroImageMat plotrecipe uses this recipe for grid lines if `grid=true`.
@recipe function f(wcsg::WCSGrid, gridspec=wcsgridspec(wcsg))
    label --> ""
    xs, ys = wcsgridlines(gridspec)

    if haskey(plotattributes, :foreground_color_grid) 
        color --> plotattributes[:foreground_color_grid]
    elseif haskey(plotattributes, :foreground_color) 
        color --> plotattributes[:foreground_color]
    else
        color --> :black
    end
    if haskey(plotattributes, :foreground_color_text) 
        textcolor = plotattributes[:foreground_color_text]
    else
        textcolor = plotattributes[:color]
    end
    annotate = haskey(plotattributes, :gridlabels) && plotattributes[:gridlabels]

    xguide --> ctype_label(wcs(wcsg.img, wcsg.wcsn).ctype[wcsax(wcsg.img, dims(wcsg.img,1))], wcs(wcsg.img, wcsg.wcsn).radesys)
    yguide --> ctype_label(wcs(wcsg.img, wcsg.wcsn).ctype[wcsax(wcsg.img, dims(wcsg.img,2))], wcs(wcsg.img, wcsg.wcsn).radesys)

    xlims --> wcsg.extent[1], wcsg.extent[2]
    ylims --> wcsg.extent[3], wcsg.extent[4]

    grid := false
    tickdirection := :none

    xticks --> wcsticks(wcsg, 1, gridspec)
    yticks --> wcsticks(wcsg, 2, gridspec)

    @series xs, ys

    # We can optionally annotate the grid with their coordinates.
    # These come after the grid lines so they appear overtop.
    if annotate
        @series begin
            # TODO: why is this reverse necessary?
            rotations = reverse(rad2deg.(gridspec.annotations1θ))
            ticklabels = wcslabels(wcs(wcsg.img), 1, gridspec.annotations1w)
            seriestype := :line
            linewidth := 0
            # TODO: we need to use requires to load in Plots for the necessary text control. Future versions of RecipesBase might fix this.
            series_annotations := [
                Main.Plots.text(" $l", :right, :bottom, textcolor, 8, rotation=(-95 <= r <= 95) ? r : r+180)
                for (l, r) in zip(ticklabels, rotations)
            ]
            gridspec.annotations1x, gridspec.annotations1y
        end
        @series begin
            rotations  = rad2deg.(gridspec.annotations2θ)
            ticklabels = wcslabels(wcs(wcsg.img), 2, gridspec.annotations2w)
            seriestype := :line
            linewidth := 0
            series_annotations := [
                Main.Plots.text(" $l", :right, :bottom, textcolor, 8, rotation=(-95 <= r <= 95) ? r : r+180)
                for (l, r) in zip(ticklabels, rotations)
            ]
            gridspec.annotations2x, gridspec.annotations2y
        end

    end

    return
end

# Helper: true if all elements in vector are equal to each other.
allequal(itr) = all(==(first(itr)), itr)

# This function is responsible for actually laying out grid lines for a WCSGrid,
# ensuring they don't exceed the plot bounds, finding where they intersect the axes,
# and picking tick locations at the appropriate intersections with the left and 
# bottom axes.
function wcsgridspec(wsg::WCSGrid)
    # Most of the complexity of this function is making sure everything
    # generalizes to N different, possiby skewed axes, where a change in
    # the opposite coordinate or even an unplotted coordinate affects
    # the grid.
    
    # x and y denote pixel coordinates (along `ax`), u and v are world coordinates roughly along same.
    minx, maxx, miny, maxy = wsg.extent

    # Find the extent of this slice in world coordinates
    posxy = [
        minx minx maxx maxx
        miny maxy miny maxy
    ]
    posuv = pix_to_world(wsg.img, posxy; wsg.wcsn, parent=true)
    (minu, maxu), (minv, maxv) = extrema(posuv, dims=2)

    # In general, grid can be curved when plotted back against the image,
    # so we will need to sample multiple points along the grid.
    # TODO: find a good heuristic for this based on the curvature.
    N_points = 50
    urange = range(minu, maxu, length=N_points)
    vrange = range(minv, maxv, length=N_points)

    # Find nice grid spacings using PlotUtils.optimize_ticks
    # These heuristics can probably be improved
    # TODO: this does not handle coordinates that wrap around
    Q=[(1.0,1.0), (3.0, 0.8), (2.0, 0.7), (5.0, 0.5)] 
    k_min = 3
    k_ideal = 5
    k_max = 10

    tickpos2x = Float64[]
    tickpos2w = Float64[]
    gridlinesxy2 = NTuple{2,Vector{Float64}}[]
    # Not all grid lines will intersect the x & y axes nicely.
    # If we don't get enough valid tick marks (at least 2) loop again
    # requesting more locations up to three times.
    local tickposv
    j = 5
    while length(tickpos2x) < 2 && j > 0
        k_min += 2
        k_ideal += 2
        k_max += 2
        j -= 1

        tickposv = optimize_ticks(6minv, 6maxv; Q, k_min, k_ideal, k_max)[1]./6

        empty!(tickpos2x)
        empty!(tickpos2w)
        empty!(gridlinesxy2)
        for tickv in tickposv
            # Make sure we handle unplotted slices correctly.
            griduv = repeat(posuv[:,1], 1, N_points)
            griduv[1,:] .= urange
            griduv[2,:] .= tickv
            posxy = world_to_pix(wsg.img, griduv; wsg.wcsn, parent=true)

            # Now that we have the grid in pixel coordinates, 
            # if we find out where the grid intersects the axes we can put
            # the labels in the correct spot
            
            # We can use these masks to determine where, and in what direction
            # the gridlines leave the plot extent
            in_horz_ax = minx .<=  posxy[1,:] .<= maxx
            in_vert_ax = miny .<=  posxy[2,:] .<= maxy
            in_axes = in_horz_ax .& in_vert_ax
            if count(in_axes) < 2
                continue
            elseif all(in_axes)
                point_entered = [
                    posxy[1,begin]
                    posxy[2,begin]
                ]
                point_exitted = [
                    posxy[1,end]
                    posxy[2,end]
                ]
            elseif allequal(posxy[1,findfirst(in_axes):findlast(in_axes)])
                point_entered = [
                    posxy[1,max(begin,findfirst(in_axes)-1)]
                    # posxy[2,max(begin,findfirst(in_axes)-1)]
                    miny
                ]
                point_exitted = [
                    posxy[1,min(end,findlast(in_axes)+1)]
                    # posxy[2,min(end,findlast(in_axes)+1)]
                    maxy
                ]
            # Vertical grid lines
            elseif allequal(posxy[2,findfirst(in_axes):findlast(in_axes)])
                point_entered = [
                    minx #posxy[1,max(begin,findfirst(in_axes)-1)]
                    posxy[2,max(begin,findfirst(in_axes)-1)]
                ]
                point_exitted = [
                    maxx #posxy[1,min(end,findlast(in_axes)+1)]
                    posxy[2,min(end,findlast(in_axes)+1)]
                ]
            else
                # Use the masks to pick an x,y point inside the axes and an
                # x,y point outside the axes.
                i = findfirst(in_axes)
                x1 = posxy[1,i]
                y1 = posxy[2,i]
                x2 = posxy[1,i+1]
                y2 = posxy[2,i+1]
                if x2-x1 ≈ 0
                    @warn "undef slope"
                end

                # Fit a line where we cross the axis
                m1 = (y2-y1)/(x2-x1)
                b1 = y1-m1*x1
                # If the line enters via the vertical axes...
                if findfirst(in_vert_ax) <= findfirst(in_horz_ax)
                    # Then we simply evaluate it at that axis
                    x = abs(x1-maxx) < abs(x1-minx) ? maxx : minx
                    x = clamp(x,minx,maxx)
                    y = m1*x+b1
                else
                    # We must find where it enters the plot from
                    # bottom or top
                    x = abs(y1-maxy) < abs(y1-miny) ? (maxy-b1)/m1 : (miny-b1)/m1
                    x = clamp(x,minx,maxx)
                    y = m1*x+b1
                end
            
                # From here, do a linear fit to find the intersection with the axis.
                point_entered = [
                    x
                    y
                ]


                # Use the masks to pick an x,y point inside the axes and an
                # x,y point outside the axes.
                i = findlast(in_axes)
                x1 = posxy[1,i-1]
                y1 = posxy[2,i-1]
                x2 = posxy[1,i]
                y2 = posxy[2,i]
                if x2-x1 ≈ 0
                    @warn "undef slope"
                end

                # Fit a line where we cross the axis
                m2 = (y2-y1)/(x2-x1)
                b2 = y2-m2*x2
                if findlast(in_vert_ax) > findlast(in_horz_ax)
                    # Then we simply evaluate it at that axis
                    x = abs(x1-maxx) < abs(x1-minx) ? maxx : minx
                    x = clamp(x,minx,maxx)
                    y = m2*x+b2
                else
                    # We must find where it enters the plot from
                    # bottom or top
                    x = abs(y1-maxy) < abs(y1-miny) ? (maxy-b2)/m2 : (miny-b2)/m2
                    x = clamp(x,minx,maxx)
                    y = m2*x+b2
                end
            
                # From here, do a linear fit to find the intersection with the axis.
                point_exitted = [
                    x 
                    y
                ]
            end


            if point_entered[1] == minx
                push!(tickpos2x, point_entered[2])
                push!(tickpos2w, tickv)
            end
            if point_exitted[1] == minx
                push!(tickpos2x, point_exitted[2])
                push!(tickpos2w, tickv)
            end


            posxy_neat = [point_entered  posxy[[1,2],in_axes] point_exitted]
            # posxy_neat = posxy
            # TODO: do unplotted other axes also need a fit?

            gridlinexy = (
                posxy_neat[1,:],
                posxy_neat[2,:]
            )
            push!(gridlinesxy2, gridlinexy)
        end
    end

    # Then do the opposite coordinate
    k_min = 3
    k_ideal = 5
    k_max = 10
    tickpos1x = Float64[]
    tickpos1w = Float64[]
    gridlinesxy1 = NTuple{2,Vector{Float64}}[]
    # Not all grid lines will intersect the x & y axes nicely.
    # If we don't get enough valid tick marks (at least 2) loop again
    # requesting more locations up to three times.
    local tickposu
    j = 5
    while length(tickpos1x) < 2 && j > 0
        k_min += 2
        k_ideal += 2
        k_max += 2
        j -= 1

        tickposu = optimize_ticks(6minu, 6maxu; Q, k_min, k_ideal, k_max)[1]./6

        empty!(tickpos1x)
        empty!(tickpos1w)
        empty!(gridlinesxy1)
        for ticku in tickposu
            # Make sure we handle unplotted slices correctly.
            griduv = repeat(posuv[:,1], 1, N_points)
            griduv[1,:] .= ticku
            griduv[2,:] .= vrange
            posxy = world_to_pix(wsg.img, griduv; wsg.wcsn, parent=true)           

            # Now that we have the grid in pixel coordinates, 
            # if we find out where the grid intersects the axes we can put
            # the labels in the correct spot

            # We can use these masks to determine where, and in what direction
            # the gridlines leave the plot extent
            in_horz_ax = minx .<=  posxy[1,:] .<= maxx
            in_vert_ax = miny .<=  posxy[2,:] .<= maxy
            in_axes = in_horz_ax .& in_vert_ax


            if count(in_axes) < 2
                continue
            elseif all(in_axes)
                point_entered = [
                    posxy[1,begin]
                    posxy[2,begin]
                ]
                point_exitted = [
                    posxy[1,end]
                    posxy[2,end]
                ]
            # Horizontal grid lines
            elseif allequal(posxy[1,findfirst(in_axes):findlast(in_axes)])
                point_entered = [
                    posxy[1,findfirst(in_axes)]
                    miny
                ]
                point_exitted = [
                    posxy[1,findlast(in_axes)]
                    maxy
                ]
                # push!(tickpos1x, posxy[1,findfirst(in_axes)])
                # push!(tickpos1w, ticku)
            # Vertical grid lines
            elseif allequal(posxy[2,findfirst(in_axes):findlast(in_axes)])
                point_entered = [
                    minx
                    posxy[2,findfirst(in_axes)]
                ]
                point_exitted = [
                    maxx
                    posxy[2,findfirst(in_axes)]
                ]
            else
                # Use the masks to pick an x,y point inside the axes and an
                # x,y point outside the axes.
                i = findfirst(in_axes)
                x1 = posxy[1,i]
                y1 = posxy[2,i]
                x2 = posxy[1,i+1]
                y2 = posxy[2,i+1]
                if x2-x1 ≈ 0
                    @warn "undef slope"
                end

                # Fit a line where we cross the axis
                m1 = (y2-y1)/(x2-x1)
                b1 = y1-m1*x1
                # If the line enters via the vertical axes...
                if findfirst(in_vert_ax) < findfirst(in_horz_ax)
                    # Then we simply evaluate it at that axis
                    x = abs(x1-maxx) < abs(x1-minx) ? maxx : minx
                    x = clamp(x,minx,maxx)
                    y = m1*x+b1
                else
                    # We must find where it enters the plot from
                    # bottom or top
                    x = abs(y1-maxy) < abs(y1-miny) ? (maxy-b1)/m1 : (miny-b1)/m1
                    x = clamp(x,minx,maxx)
                    y = m1*x+b1
                end
            
                # From here, do a linear fit to find the intersection with the axis.
                point_entered = [
                    x
                    y
                ]

                # Use the masks to pick an x,y point inside the axes and an
                # x,y point outside the axes.
                i = findlast(in_axes)
                x1 = posxy[1,i-1]
                y1 = posxy[2,i-1]
                x2 = posxy[1,i]
                y2 = posxy[2,i]
                if x2-x1 ≈ 0
                    @warn "undef slope"
                end

                # Fit a line where we cross the axis
                m2 = (y2-y1)/(x2-x1)
                b2 = y2-m2*x2
                if findlast(in_vert_ax) > findlast(in_horz_ax)
                    # Then we simply evaluate it at that axis
                    x = abs(x1-maxx) < abs(x1-minx) ? maxx : minx
                    x = clamp(x,minx,maxx)
                    y = m2*x+b2
                else
                    # We must find where it enters the plot from
                    # bottom or top
                    x = abs(y1-maxy) < abs(y1-miny) ? (maxy-b2)/m2 : (miny-b2)/m2
                    x = clamp(x,minx,maxx)
                    y = m2*x+b2
                end
            
                # From here, do a linear fit to find the intersection with the axis.
                point_exitted = [
                    x 
                    y
                ]
            end

            posxy_neat = [point_entered  posxy[[1,2],in_axes] point_exitted]
            # TODO: do unplotted other axes also need a fit?

            if point_entered[2] == miny
                push!(tickpos1x, point_entered[1])
                push!(tickpos1w, ticku)
            end
            if point_exitted[2] == miny
                push!(tickpos1x, point_exitted[1])
                push!(tickpos1w, ticku)
            end

            gridlinexy = (
                posxy_neat[1,:],
                posxy_neat[2,:]
            )
            push!(gridlinesxy1, gridlinexy)
        end
    end

    # Grid annotations are simpler:
    annotations1w = Float64[]
    annotations1x = Float64[]
    annotations1y = Float64[]
    annotations1θ = Float64[]
    for ticku in tickposu
        # Make sure we handle unplotted slices correctly.
        griduv = posuv[:,1]
        griduv[1] = ticku
        griduv[2] = mean(vrange)
        posxy = world_to_pix(wsg.img, griduv; wsg.wcsn, parent=true)
        if !(minx < posxy[1] < maxx) ||
            !(miny < posxy[2] < maxy)
            continue
        end
        push!(annotations1w, ticku)
        push!(annotations1x, posxy[1])
        push!(annotations1y, posxy[2])

        # Now find slope (TODO: stepsize)
        # griduv[ax[2]] -= 1
        griduv[2] += 0.1step(vrange)
        posxy2 = world_to_pix(wsg.img, griduv; wsg.wcsn, parent=true)
        θ = atan(
            posxy2[2] - posxy[2],
            posxy2[1] - posxy[1],
        )
        push!(annotations1θ, θ)
    end
    annotations2w = Float64[]
    annotations2x = Float64[]
    annotations2y = Float64[]
    annotations2θ = Float64[]
    for tickv in tickposv
        # Make sure we handle unplotted slices correctly.
        griduv = posuv[:,1]
        griduv[1] = mean(urange)
        griduv[2] = tickv
        posxy = world_to_pix(wsg.img, griduv; wsg.wcsn, parent=true)
        if !(minx < posxy[1] < maxx) ||
            !(miny < posxy[2] < maxy)
            continue
        end
        push!(annotations2w, tickv)
        push!(annotations2x, posxy[1])
        push!(annotations2y, posxy[2])

        griduv[1] += 0.1step(urange)
        posxy2 = world_to_pix(wsg.img, griduv; wsg.wcsn, parent=true)
        θ = atan(
            posxy2[2] - posxy[2],
            posxy2[1] - posxy[1],
        )
        push!(annotations2θ, θ)
    end

    return (;
        gridlinesxy1,
        gridlinesxy2,
        tickpos1x,
        tickpos1w,
        tickpos2x,
        tickpos2w,

        annotations1w,
        annotations1x,
        annotations1y,
        annotations1θ,

        annotations2w,
        annotations2x,
        annotations2y,
        annotations2θ,
    )
end

# From a WCSGrid, return just the grid lines as a single pair of x & y coordinates
# suitable for plotting.
function wcsgridlines(wcsg::WCSGrid)
    return wcsgridlines(wcsgridspec(wcsg))
end
function wcsgridlines(gridspec::NamedTuple)
    # Unroll grid lines into a single series separated by NaNs
    xs1 = mapreduce(vcat, gridspec.gridlinesxy1, init=Float64[]) do gridline
        return vcat(gridline[1], NaN)
    end
    ys1 = mapreduce(vcat, gridspec.gridlinesxy1, init=Float64[]) do gridline
        return vcat(gridline[2], NaN)
    end
    xs2 = mapreduce(vcat, gridspec.gridlinesxy2, init=Float64[]) do gridline
        return vcat(gridline[1], NaN)
    end
    ys2 = mapreduce(vcat, gridspec.gridlinesxy2, init=Float64[]) do gridline
        return vcat(gridline[2], NaN)
    end

    xs = vcat(xs1, NaN, xs2)
    ys = vcat(ys1, NaN, ys2)
    return xs, ys
end




@userplot PolQuiver
@recipe function f(h::PolQuiver)
    cube = only(h.args)
    bins = get(plotattributes, :bins, 4)
    ticklen = get(plotattributes, :ticklen, nothing)
    minpol = get(plotattributes, :minpol, 0.1)

    i = cube[Pol=At(:I)]
    q = cube[Pol=At(:Q)]
    u = cube[Pol=At(:U)]
    polinten = @. sqrt(q^2 + u^2)
    linpolfrac = polinten ./ i

    binratio=1/bins
    xs = imresize([x for x in dims(cube,1), y in dims(cube,2)], ratio=binratio)
    ys = imresize([y for x in dims(cube,1), y in dims(cube,2)], ratio=binratio)
    qx = imresize(q, ratio=binratio)
    qy = imresize(u, ratio=binratio)
    qlinpolfrac = imresize(linpolfrac, ratio=binratio)
    qpolintenr = imresize(polinten, ratio=binratio)


    # We want the longest ticks to be around 1 bin long by default.
    qmaxlen = quantile(filter(isfinite,qpolintenr), 0.98)
    if isnothing(ticklen)
        a = bins / qmaxlen
    else
        a = ticklen / qmaxlen
    end
    # Only show arrows where the data is finite, and more than a couple pixels
    # long.
    mask = (isfinite.(qpolintenr)) .& (qpolintenr .>= minpol.*qmaxlen)
    pointstmp = map(xs[mask],ys[mask],qx[mask],qy[mask]) do x,y,qxi,qyi
        return ([x, x+a*qxi, NaN], [y, y+a*qyi, NaN])
    end
    xs = reduce(vcat, getindex.(pointstmp, 1))
    ys = reduce(vcat, getindex.(pointstmp, 2))

    colors = qlinpolfrac[mask]
    if !isnothing(colors)
        line_z := repeat(colors, inner=3)
    end

    label --> ""
    color --> :turbo
    framestyle --> :box
    aspect_ratio --> 1
    linewidth --> 1.5
    colorbar --> true
    colorbar_title --> "Linear polarization fraction"

    xl = first(dims(i,2)), last(dims(i,2))
    yl = first(dims(i,1)), last(dims(i,1))
    ylims --> yl
    xlims --> xl

    @series begin
        xs, ys
    end
end

"""
    polquiver(polqube::AstroImage)

Given a data cube (of at least 2 spatial dimensions, plus a polarization axis),
plot a vector field of polarization data. 
The tick length represents the polarization intensity, sqrt(q^2 + u^2), 
and the color represents the linear polarization fraction, sqrt(q^2 + u^2) / i.

There are several ways you can adjust the appearance of the plot using keyword arguments:
* `bins` (default = 1) By how much should we bin down the polarization data before drawing the ticks? This reduced clutter from higher resolution datasets. Can be fractional.
* `ticklen` (default = bins) How long the 98th percentile arrow should be. By default, 1 bin long. Make this larger to draw longer arrows.
* `color` (default = :turbo) What colorscheme should be used for linear polarization fraction.
* `minpol` (default = 0.2) Hides arrows that are shorter than `minpol` times the 98th percentile arrow to make a cleaner image. Set to 0 to display all data.

Use `implot` and `polquiver!` to overplot polarization data over an image.
"""
polquiver
