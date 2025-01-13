module NetworkInterfaceControllers

include("interfaces.jl")
using .Interfaces
export Interface, get_interface_data

export get_interface_data

include("broker.jl")
using .Broker
export start_server, query

include("nic_preferences.jl")
using .NICPreferences

include("name_selector.jl")
using .NameSelector

# Load HwlocSelector module via and extension => avoid adding dependencies on
# Hwloc and AbstractTrees unless needed
get_hwloc_selector() = Base.get_extension(@__MODULE__, :HwlocSelector)

include("hostlists.jl")
using .Hostlists

#------------------------------------------------------------------------------
# Helper functions for Broker
#------------------------------------------------------------------------------

function julia_runtime_str()::String
    julia_str   = Base.julia_cmd().exec |> first
    project_str = Base.active_project()
    return "$(julia_str) --project=$(project_str)"
end

function broker_ip_port(ipv)
    iface = get_interface_data(ipv, loopback=true) |>
            x->NameSelector.best_interfaces(
                x,
                NICPreferences.BROKER_INTERFACE.name,
                NICPreferences.BROKER_INTERFACE.match_strategy) |>
            only
    return iface.ip, NICPreferences.BROKER_INTERFACE.port
end

function start_broker(ipv)
    ip, port = broker_port(ipv)

    t::Task = @task Broker.start_server(
        iface.ip, UInt32(NICPreferences.BROKER_INTERFACE.port)
    )
    # Run the server right away
    schedule(t)
    return iface.ip, NICPreferences.BROKER_INTERFACE.port, t
end

function broker_ip_string(ipv::Int)::String
    @assert ipv in (4, 6)

    runtime_str = julia_runtime_str()
    import_str  = "using NetworkInterfaceControllers, Sockets"
    query_str   = (4==ipv) ? "broker_ip_port(IPv4)" : "broker_ip_port(IPv6)"

    return "$(runtime_str) -e '$(import_str); println($(query_str) |> first)'"
end

function broker_port_string(ipv::Int)::String
    @assert ipv in (4, 6)

    runtime_str = julia_runtime_str()
    import_str  = "using NetworkInterfaceControllers, Sockets"
    query_str   = (4==ipv) ? "broker_ip_port(IPv4)" : "broker_ip_port(IPv6)"

    return "$(runtime_str) -e '$(import_str); println($(query_str) |> last)'"
end

function broker_startup_string(ipv::Int)::String
    @assert ipv in (4, 6)

    runtime_str = julia_runtime_str()
    import_str  = "using NetworkInterfaceControllers, Sockets"
    query_str   = (4==ipv) ? "start_broker(IPv4)" : "start_broker(IPv6)"

    return "$(runtime_str) -e '$(import_str); $(query_str) |> last |> wait'"
end

function broker_query_string(ip::String, port::Int)::String
    runtime_str = julia_runtime_str()
    import_str  = "using NetworkInterfaceControllers.Broker, Sockets"
    query_str   = "Broker.query(ip\"$(ip)\", UInt32($(port)), ifaces)"

    return "$(runtime_str) -e '$(import_str); $(query_str)'"
end

export start_broker, broker_ip_port, broker_ip_string, broker_port_string
export broker_startup_string, broker_query_string

function best_interface_hwloc_closest(
        data::Interface; pid::Union{T, Nothing}=nothing
    ) where T <: Integer
end

function best_interface_broker(
        data::Interface; broker_port::Union{T, Nothing}=nothing
    ) where T <: Integer
end

function best_interfaces(data::Vector{Interface})
    strategy = NICPreferences.selection_strategy

    if strategy == NICPreferences.PREFERRED_INTERFACE_NAME_MATCH
        return NameSelector.best_interfaces(data)
    elseif strategy == NICPreferences.PREFERRED_INTERFACE_HWLOC_CLOSEST
        HwlocSelector = get_hwloc_selector()
        if isnothing(HwlocSelector)
            @error "'Hwloc' and/or 'AbstractTrees' not loaded! Run: `import Hwloc, AbstractTrees`"
        end
        return HwlocSelector.best_interfaces(data)
    elseif strategy == NICPreferences.PREFERRED_INTERFACE_BROKER
        return best_interface_broker(data)
    else
        @error "Cannot interpret strategy: $(strategy)"
    end
end


end # module NetworkInterfaces
