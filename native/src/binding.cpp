#include "ecosystem.hpp"
#ifdef _WIN32
#include <windows.h>

#include <psapi.h>
#endif
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
using namespace godot;
class BaySimulation : public RefCounted {
    GDCLASS(BaySimulation, RefCounted)
    std::unique_ptr<bay::Engine> engine;
    static double number(Dictionary const &d, char const *k, double fallback = 0) {
        return double(d.get(k, fallback));
    }

  protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("initialize", "world"), &BaySimulation::initialize);
        ClassDB::bind_method(D_METHOD("set_controls", "controls"), &BaySimulation::set_controls);
        ClassDB::bind_method(D_METHOD("read_view", "bounds", "selected"), &BaySimulation::read_view);
        ClassDB::bind_method(D_METHOD("spawn_bait", "species", "position"), &BaySimulation::spawn_bait);
        ClassDB::bind_method(D_METHOD("shutdown"), &BaySimulation::shutdown);
        ClassDB::bind_method(D_METHOD("process_memory"), &BaySimulation::process_memory);
    }

  public:
    Dictionary process_memory() {
        Dictionary d;
#ifdef _WIN32
        PROCESS_MEMORY_COUNTERS_EX m{};
        m.cb = sizeof(m);
        if (GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS *>(&m),
                                 sizeof(m))) {
            d["working_set"] = int64_t(m.WorkingSetSize);
            d["private_bytes"] = int64_t(m.PrivateUsage);
        }
#endif
        return d;
    }
    ~BaySimulation() {
        shutdown();
    }
    void shutdown() {
        if (engine)
            engine->stop();
        engine.reset();
    }
    bool initialize(Dictionary const &world) {
        shutdown();
        engine = std::make_unique<bay::Engine>();
        auto &e = *engine;
        Vector2 origin = world["origin"];
        e.origin = {origin.x, origin.y};
        e.width = int(world["width"]);
        e.height = int(world["height"]);
        e.cell = double(world["cell"]);
        PackedByteArray mask = world["mask"];
        e.water.assign(mask.ptr(), mask.ptr() + mask.size());
        if (e.width <= 0 || e.height <= 0 || e.water.size() != size_t(e.width) * e.height) {
            shutdown();
            return false;
        }
        Array nodes = world["nodes"];
        int max_id = 0;
        for (int i = 0; i < nodes.size(); i++) {
            Dictionary d = nodes[i];
            max_id = std::max(max_id, int(d["id"]));
        }
        e.nodes.resize(max_id + 1);
        for (int i = 0; i < nodes.size(); i++) {
            Dictionary d = nodes[i];
            auto &n = e.nodes[int(d["id"])];
            n.at = {number(d, "x"), number(d, "y")};
            n.depth = number(d, "depth_m", 2);
            n.zone = int(d["zone"]);
            n.component = int(d["component"]);
            n.shore=number(d,"shore_m",100);
            n.cover = n.shore < 100 ? .4 : .1;
            Array tags=d.get("tags",Array());
            for(int t=0;t<tags.size();t++) {
                String tag=tags[t];
                if(tag.contains("mangrove") || tag.contains("grass") || tag.contains("pothole") || tag.contains("oyster") || tag.contains("structure") || tag.contains("creek")) n.cover=std::max(n.cover,.7);
            }
            PackedInt32Array neighbors = d["neighbors"];
            n.neighbors.assign(neighbors.ptr(), neighbors.ptr() + neighbors.size());
        }
        Array records = world["animals"];
        e.animals.reserve(records.size());
        for (int i = 0; i < records.size(); i++) {
            Dictionary d = records[i];
            bay::Animal a;
            a.kind = int(d["kind"]);
            a.index = int(d["index"]);
            a.id = int64_t(d["id"]);
            a.species = int(d["species"]);
            a.at = {number(d, "x"), number(d, "y")};
            a.depth = number(d, "depth", 1);
            a.size = number(d, "size", 30);
            a.hunger = number(d, "hunger", .4);
            a.energy = number(d, "energy", 1);
            a.home = int(d.get("home", -1));
            a.feeding = int(d.get("feeding", a.home));
            a.zone = int(d.get("zone", 0));
            a.school = int(d.get("school", -1));
            a.quantity = int(d.get("quantity", 1));
            a.capacity = int(d.get("capacity", a.quantity));
            a.individual = bool(d.get("individual", false));
            a.temporary = bool(d.get("temporary", false));
            a.parent_id = int64_t(d.get("parent_id", 0));
            a.alive = a.quantity > 0;
            Dictionary r = d.get("profile", Dictionary());
            a.profile.cruise = number(r, "cruise_mph", 1) * .44704;
            a.profile.burst = number(r, "burst_mph", 5) * .44704;
            a.profile.detect = number(r, "detect_ft", 100) * .3048;
            a.profile.reach = number(r, "strike_ft", 3) * .3048 + a.size * .003;
            a.profile.lunge = number(r, "lunge_ft", 20) * .3048;
            a.profile.chance = number(r, "capture_chance", .6);
            a.profile.gape = number(r, "gape", .4);
            a.profile.cone_cos=std::cos(number(r,"field_of_view_degrees",160)*3.141592653589793/360);
            a.profile.awareness=number(r,"close_awareness_fraction",.2);
            a.profile.awareness_cap=number(r,"close_awareness_cap_ft",20)*.3048;
            a.profile.consume = number(r, "consume_seconds", 2);
            a.profile.cooldown = number(r, "attack_cooldown_seconds", 1.5);
            String style = r.get("style", "patrol");
            a.profile.style =
                style == "ambush" || style == "intercept"
                    ? 1
                    : (style == "bottom_ambush" ? 2
                                                : (style == "structure" || style == "bottom_shark" ? 3 : 0));
            e.animals.push_back(std::move(a));
        }
        Dictionary ecology=world.get("ecology",Dictionary());
        e.bait_limit=int(number(ecology,"bait_record_limit",48000));
        e.escape_cap=int(number(ecology,"escapees_per_school",6));
        e.detach_min=int(number(ecology,"detach_min",1));e.detach_max=std::max(e.detach_min,int(number(ecology,"detach_max",3)));
        e.detach_interval=std::max(3.0,number(ecology,"detach_interval_seconds",6));
        e.pressure_range=number(ecology,"school_pressure_ft",16)*.3048;
        Array modes=ecology.get("aggregate_prey_modes",Array());
        for(int i=0;i<std::min(8,int(modes.size()));i++) e.prey_modes[i]=String(modes[i])=="breakaway"?1:0;
        Dictionary tuning = world.get("attack_resolution", Dictionary());
        e.hit_min = number(tuning, "minimum", .15);
        e.hit_max = number(tuning, "maximum", .95);
        e.energy_weight = number(tuning, "energy_weight", .18);
        e.cover_weight = number(tuning, "cover_weight", .18);
        if (e.nodes.empty() || e.animals.empty()) {
            shutdown();
            return false;
        }
        e.start(uint64_t(int64_t(world.get("seed", 18472))));
        return true;
    }
    void set_controls(Dictionary const &d) {
        if (!engine)
            return;
        bay::Controls c;
        c.speed = number(d, "speed", 1);
        c.tide = number(d, "tide", 0);
        c.cpu_ms = number(d, "cpu_ms", 12);
        c.detailed = number(d, "detailed", 700);
        c.intermediate = number(d, "intermediate", 2200);
        c.hysteresis = number(d, "hysteresis", 150);
        c.selected = int(d.get("selected", -1));
        c.lod = bool(d.get("lod", true));
        Vector2 b = d.get("boat", Vector2()), v = d.get("camera", b);
        c.boat = {b.x, b.y};
        c.camera = {v.x, v.y};
        engine->control(c);
    }
    void spawn_bait(int species, Vector2 at) {
        if (engine && species >= 0 && species < 8)
            engine->spawn(species, {at.x, at.y});
    }
    Dictionary read_view(Rect2 bounds, int selected) {
        Dictionary result;
        if (!engine)
            return result;
        auto snap = engine->snapshot();
        if (!snap)
            return result;
        PackedFloat64Array data;
        Array dots;
        std::vector<std::vector<Vector2>> groups(17);
        bool overview = bounds.size.y > 4000;
        int target = -1;
        for (auto const &r : snap->rows)
            if (r.code == selected) {
                target = r.target_code;
                break;
            }
        for (auto const &r : snap->rows) {
            bool chosen = r.code == selected || r.code == target;
            if (r.kind == 3 && !chosen)
                continue;
            bool visible = r.alive && bounds.has_point(Vector2(r.at.x, r.at.y));
            if (overview && visible) {
                int group = r.kind == 0 ? r.species : (r.kind == 1 ? 8 + (r.temporary ? 8 : r.species) : -1);
                if (group >= 0 && group < 17) {
                    groups[group].push_back(Vector2(r.at.x - bounds.size.y / 1080.0, r.at.y));
                    groups[group].push_back(Vector2(r.at.x + bounds.size.y / 1080.0, r.at.y));
                }
            }
            if (!(r.kind == 2 && bounds.has_area()) && !chosen && (!visible || overview))
                continue;
            double row[] = {double(r.code),
                            double(r.id),
                            double(r.generation),
                            double(r.species),
                            r.at.x,
                            r.at.y,
                            r.velocity.x,
                            r.velocity.y,
                            r.depth,
                            r.holding,
                            r.target_depth,
                            r.bottom,
                            r.size,
                            r.hunger,
                            r.energy,
                            r.fear,
                            double(r.state),
                            double(r.tier),
                            double(r.zone),
                            double(r.school),
                            double(r.quantity),
                            double(r.escapees),
                            double(r.parent_id),
                            double(r.target_code),
                            double(r.target_id),
                            double(r.captures),
                            double(r.misses),
                            double(r.attempts),
                            r.destination.x,
                            r.destination.y,
                            double(r.alive),
                            double(r.temporary),
                            double(r.individual),
                            r.spread,
                            double(r.event),
                            double(r.home),
                            double(r.feeding),r.heading.x,r.heading.y,r.major,r.minor,r.detect,r.awareness,r.cone_cos,
                            double(r.targeters),double(r.child_targeters),r.threat.x,r.threat.y};
            for (double value : row)
                data.push_back(value);
        }
        for (auto const &group : groups) {
            PackedVector2Array points;
            points.resize(group.size());
            for (size_t i = 0; i < group.size(); i++)
                points.set(i, group[i]);
            dots.append(points);
        }
        Dictionary stats;
        stats["time"] = snap->time;
        stats["requested"] = snap->requested;
        stats["backlog"] = std::max(0.0, snap->requested - snap->time);
        stats["cpu_ms"] = snap->cpu_ms;
        stats["wall"] = snap->wall;
        stats["events"] = int64_t(snap->events);
        stats["consumed"] = int64_t(snap->consumed);
        stats["units"] = int64_t(snap->units);
        stats["initial_units"] = int64_t(snap->initial_units);
        stats["created"] = int64_t(snap->created);
        stats["conservation_error"] = int64_t(snap->units + snap->consumed) - int64_t(snap->initial_units + snap->created);
        stats["detached"] = int64_t(snap->detached);
        stats["rejoined"] = int64_t(snap->rejoined);
        stats["navigation_ms"] = snap->nav_ms;
        stats["hunting_ms"] = snap->hunting_ms;
        stats["prey_units"]=int64_t(snap->prey_units);
        stats["records"]=int64_t(snap->rows.size());
        Array bait_counts;for(int n:snap->bait_counts) bait_counts.append(n);
        stats["bait_counts"]=bait_counts;
        stats["queries"] = int64_t(snap->queries);
        stats["routes"] = int64_t(snap->routes);
        stats["memory_bytes"] = int64_t(snap->memory);
        Array counts, pop;
        for (int n : snap->counts)
            counts.append(n);
        for (int n : snap->alive)
            pop.append(n);
        stats["levels"] = counts;
        stats["population"] = pop;
        result["rows"] = data;
        result["dots"] = dots;
        result["stats"] = stats;
        return result;
    }
};
void initialize_bay(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE)
        ClassDB::register_class<BaySimulation>();
}
void uninitialize_bay(ModuleInitializationLevel) {}
extern "C" {
GDExtensionBool GDE_EXPORT bay_ecosystem_init(GDExtensionInterfaceGetProcAddress proc,
                                              GDExtensionClassLibraryPtr library,
                                              GDExtensionInitialization *init) {
    GDExtensionBinding::InitObject object(proc, library, init);
    object.register_initializer(initialize_bay);
    object.register_terminator(uninitialize_bay);
    object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return object.init();
}
}
