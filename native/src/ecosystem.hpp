#pragma once
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <queue>
#include <random>
#include <thread>
#include <unordered_map>
#include <vector>
namespace bay {
struct V {
    double x = 0, y = 0;
    V operator+(V b) const {
        return {x + b.x, y + b.y};
    }
    V operator-(V b) const {
        return {x - b.x, y - b.y};
    }
    V operator*(double s) const {
        return {x * s, y * s};
    }
    double len2() const {
        return x * x + y * y;
    }
    double len() const {
        return std::sqrt(len2());
    }
    V unit() const {
        double n = len();
        return n > 1e-9 ? *this * (1 / n) : V{};
    }
};
inline double clamp(double x, double lo, double hi) {
    return std::max(lo, std::min(hi, x));
}
struct Handle {
    uint32_t slot = UINT32_MAX, generation = 0;
    bool operator==(Handle b) const {
        return slot == b.slot && generation == b.generation;
    }
};
struct Profile {
    double cruise = .5, burst = 2, detect = 30, reach = 1.2, lunge = 8, gape = .4, chance = .6,
           cooldown = 1.5, consume = 2, rest = 6, cone_cos = .1736481777, awareness = .2, awareness_cap = 6;
    double hunger_factor = 1, feeding_fraction = .25;
    int feeding_mode = 0; // forward, cover/home, school, bottom
    int style = 0;
};
struct Habitat {
    uint32_t kind = 0;
    std::vector<V> samples;
    std::vector<double> radii;
};
struct Node {
    V at;
    double depth = 2, cover = .1, shore = 100, food = 1, food_time = 0;
    V trail_at, trail_heading, noise_at;
    double trail_time = -10000, trail_size = 0, noise_time = -10000;
    int trail_species = 0;
    int zone = 0, component = 0;
    std::vector<int> neighbors, areas;
};
struct Animal {
    uint64_t id = 0, parent_id = 0;
    uint32_t generation = 1, token = 0;
    int kind = 0, index = 0, species = 0, state = 0, tier = 2, zone = 0, home = -1, feeding = -1, school = -1,
        node = -1;
    bool alive = true, individual = false, temporary = false, return_home = false, motivated = false,
         ambush_committed = false;
    int quantity = 1, capacity = 1, escapees = 0, captures = 0, misses = 0, attempts = 0;
    V at, velocity, heading{1, 0}, home_at, threat, escape_heading;
    double depth = 1, holding = 1, target_depth = 1, bottom = 2, size = 30, hunger = .5, energy = 1, fear = 0,
           spread = 0;
    double last_capture = -1, recover_until = 0, route_initial_speed = 0, route_relax = 0;
    double tracked_at = 0, reaction_at = 0, shelter_hold = 0, sync_time = 0, recruitment = 0, merge_at = 0,
           last = 0, due = 0, decision = 0, detect_at = 0, attack_at = 0, until = 0, threat_until = 0,
           pursuit_started = 0, detached_at = 0, regroup_at = 0, route_started = 0, route_speed = .5,
           route_length = 0, scatter_at = 0;
    Handle target, nearby_food, inspecting, rejected;
    double inspect_until = 0, inspect_at = 0, rejected_until = 0;
    int previous_patrol_node = -1, patrol_area = -1;
    uint32_t habitat_mask = 0;
    double area_until = 0;
    std::vector<int> preferred_areas;
    int circuit[4] = {-1, -1, -1, -1}, circuit_count = 0, circuit_cursor = 0;
    V food_seen_at, food_seen_heading, learned_food;
    double last_attack_noise = -10000;
    double food_seen_time = -10000, memory_until = -1, trail_due = 0, cue_seen_time = -10000;
    Profile profile;
    std::vector<V> path;
    std::vector<double> lengths;
    std::vector<int64_t> cells;
    int event = 0;
};
struct Event {
    double at;
    uint32_t slot, generation, token;
    bool operator<(Event const &b) const {
        return at > b.at || (at == b.at && slot > b.slot);
    }
};
struct Row {
    int code, kind, index, species, state, tier, zone, school, quantity, escapees, captures, misses, attempts,
        target_code, event, home, feeding;
    uint64_t id, parent_id, target_id;
    uint32_t generation;
    bool alive, temporary, individual, hunt_eligible = false, motivated = false, school_prey = false;
    int target_slot = -1;
    double consume_left = 0, recover_left = 0, swim_speed = 0, capture_age = -1;
    V at, velocity, heading, destination, threat;
    double major = 0, minor = 0, detect = 0, awareness = 0, cone_cos = 0;
    int targeters = 0, child_targeters = 0;
    double depth, holding, target_depth, bottom, size, hunger, energy, fear, spread;
};
struct Snapshot {
    std::vector<Row> rows;
    double time = 0, requested = 0, cpu_ms = 0, wall = 0, achieved = 0, nav_ms = 0, hunting_ms = 0;
    uint64_t units = 0, initial_units = 0, created = 0, events = 0, consumed = 0, detached = 0, rejoined = 0,
             queries = 0, routes = 0;
    int counts[3] = {}, alive[4] = {}, bait_counts[3] = {};
    uint64_t prey_units = 0;
    size_t memory = 0;
};
struct Controls {
    double speed = 1, tide = 0, detailed = 700, intermediate = 2200, hysteresis = 150, cpu_ms = 12;
    V boat, camera;
    int selected = -1;
    bool lod = true;
};
struct Command {
    int kind = 0, species = 0;
    V at;
};
struct School {
    V goal;
    double until = 0;
    int node = -1;
};
class Engine {
    friend struct EngineTest;

  public:
    double hunger_rate = .00096, pursuit_hunger_factor = 1.25, hunt_start = .25, hunt_stop = .12;
    double meal_base = .02, meal_ratio = .9, meal_min = .025, meal_max = .6, post_meal_seconds = 2;
    double hit_min = .15, hit_max = .95, energy_weight = .18, cover_weight = .18;
    int bait_limit = 48000, escape_cap = 6, detach_min = 1, detach_max = 3;
    double trail_lifetime = 120, trail_radius = 35, noise_lifetime = 12, noise_radius = 80,
           food_memory_seconds = 1200;
    double detach_interval = 6, pressure_range = 5;
    // 0: explicitly direct aggregate, 1: breakaway school. Individuals always edible.
    int prey_modes[8] = {0, 1, 1, 1, 0, 0, 1, 1};
    std::vector<Animal> animals;
    std::vector<Node> nodes;
    std::vector<Habitat> habitats;
    std::vector<uint8_t> water;
    int width = 0, height = 0;
    double cell = 32;
    V origin;
    ~Engine() {
        stop();
    }
    void start(uint64_t seed);
    void stop();
    void control(Controls const &c);
    void spawn(int species, V at);
    std::shared_ptr<const Snapshot> snapshot() const {
        return std::atomic_load(&published);
    }

  private:
    std::thread worker;
    mutable std::mutex mutex;
    std::condition_variable cv;
    std::atomic<bool> stopping{false};
    Controls requested_controls, controls;
    std::vector<Command> commands;
    std::shared_ptr<const Snapshot> published;
    std::priority_queue<Event> events;
    std::unordered_map<int64_t, std::vector<uint32_t>> spatial, node_cells;
    std::unordered_map<uint64_t, uint32_t> bait_ids;
    std::unordered_map<int, School> schools;
    std::unordered_map<int, int> code_slots;
    std::vector<uint32_t> free_bait, query_marks;
    uint32_t query_stamp = 0;
    std::mt19937_64 rng;
    int next_bait_index = 0;
    double hunting_total = 0;
    double sim = 0, requested = 0, cpu_total = 0, nav_total = 0, wall_total = 0;
    uint64_t initial_units = 0, created = 0, next_bait_id = 1, event_count = 0, consumed = 0, detached = 0,
             rejoined = 0, query_count = 0, route_count = 0;
    std::vector<double> costs;
    std::vector<int> parents;
    std::vector<uint32_t> visited;
    uint32_t search_stamp = 0;
    void loop();
    void publish();
    void schedule(uint32_t slot, double at);
    void update(uint32_t slot);
    void advance(Animal &a, double time);
    V position(Animal const &a, double time) const;
    double travel_distance(Animal const &a, double time) const;
    double swimming_speed(Animal const &a, double time) const;
    void feeding_glide(Animal &a);
    double interval(int tier) const;
    int detail(Animal const &a) const;
    bool valid(Handle h) const {
        return h.slot < animals.size() && animals[h.slot].alive && animals[h.slot].generation == h.generation;
    }
    Handle handle(uint32_t slot) const {
        return {slot, animals[slot].generation};
    }
    double random() {
        return std::generate_canonical<double, 53>(rng);
    }
    bool wet(V at) const;
    bool clear(V from, V to) const;
    int nearest(V at, int component = -1) const;
    double bed(V at, int node) const;
    void route(Animal &a, V goal, int target_node, double speed);
    V sample(int node, double radius);
    void occupancy(uint32_t slot);
    void remove_occupancy(uint32_t slot);
    void query(V at, double radius, std::vector<uint32_t> &result);
    void plan(Animal &a);
    void habitat_circuit(Animal &a);
    void shelter(Animal &a);
    bool breakaway(Animal const &a) const;
    V axes(Animal const &a) const;
    V prey_point(Animal const &prey, V observer) const;
    bool senses(Animal const &a, Animal const &prey) const;
    Handle acquire(uint32_t slot, bool edible_only = false, bool curious = false);
    bool inspect_prey(uint32_t slot);
    void hunt(uint32_t slot, double dt);
    void relaxed_patrol(uint32_t slot);
    bool investigate(Animal &a);
    void bait(uint32_t slot, double dt);
    bool eat(uint32_t slot);
    void retire(uint32_t slot);
    void scatter(uint32_t slot, V threat);
    uint32_t add_bait(Animal a);
    void steer(Animal &a, V goal, double dt, double speed);
    void attack(uint32_t slot);
    int code(Animal const &a) const {
        return a.kind * 1000000 + a.index;
    }
};
} // namespace bay
