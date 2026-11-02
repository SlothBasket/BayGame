#include "ecosystem.hpp"
namespace bay {
using Clock = std::chrono::steady_clock;
static double seconds(Clock::duration d) {
    return std::chrono::duration<double>(d).count();
}
static int64_t key(int x, int y) {
    return int64_t(uint64_t(uint32_t(x)) << 32 | uint32_t(y));
}
bool Engine::wet(V p) const {
    int x = int(std::floor((p.x - origin.x) / cell)), y = int(std::floor((p.y - origin.y) / cell));
    return x >= 0 && y >= 0 && x < width && y < height && water[size_t(y) * width + x] != 0;
}
bool Engine::clear(V a, V b) const {
    V d = b - a;
    int x = int(std::floor((a.x - origin.x) / cell)), y = int(std::floor((a.y - origin.y) / cell)),
        ex = int(std::floor((b.x - origin.x) / cell)), ey = int(std::floor((b.y - origin.y) / cell));
    int sx = d.x > 0 ? 1 : -1, sy = d.y > 0 ? 1 : -1;
    double tx = d.x != 0 ? (origin.x + (x + (sx > 0)) * cell - a.x) / d.x : INFINITY,
           ty = d.y != 0 ? (origin.y + (y + (sy > 0)) * cell - a.y) / d.y : INFINITY,
           dx = d.x != 0 ? cell / std::abs(d.x) : INFINITY, dy = d.y != 0 ? cell / std::abs(d.y) : INFINITY;
    auto w = [&](int xx, int yy) {
        return xx >= 0 && yy >= 0 && xx < width && yy < height && water[size_t(yy) * width + xx] != 0;
    };
    for (int n = std::abs(ex - x) + std::abs(ey - y) + 4; n-- > 0;) {
        if (!w(x, y))
            return false;
        if (x == ex && y == ey)
            return true;
        // A negative-direction endpoint on a cell edge belongs to floor(endpoint),
        // not the next cell beyond the segment.
        if (std::min(tx, ty) >= 1.0)
            return w(ex, ey);
        if (std::abs(tx - ty) < 1e-8) {
            if (!w(x + sx, y) || !w(x, y + sy))
                return false;
            x += sx;
            y += sy;
            tx += dx;
            ty += dy;
        } else if (tx < ty) {
            x += sx;
            tx += dx;
        } else {
            y += sy;
            ty += dy;
        }
    }
    return false;
}
int Engine::nearest(V at, int component) const {
    int cx = int(std::floor(at.x / 256)), cy = int(std::floor(at.y / 256)), best = -1;
    double dist = INFINITY;
    for (int ring = 0; ring < 5; ring++) {
        for (int y = -ring; y <= ring; y++)
            for (int x = -ring; x <= ring; x++) {
                if (ring && std::abs(x) != ring && std::abs(y) != ring)
                    continue;
                auto it = node_cells.find(key(cx + x, cy + y));
                if (it == node_cells.end())
                    continue;
                for (auto i : it->second) {
                    auto const &n = nodes[i];
                    if (component >= 0 && n.component != component)
                        continue;
                    double d = (n.at - at).len2();
                    if (d < dist && clear(at, n.at)) {
                        best = int(i);
                        dist = d;
                    }
                }
            }
        if (best >= 0 && dist < (ring * 256.0) * (ring * 256.0))
            break;
    }
    return best;
}
double Engine::bed(V at, int node) const {
    int n = nearest(at, node >= 0 ? nodes[node].component : -1);
    return std::max(.1, (n >= 0 ? nodes[n].depth : 2) + controls.tide);
}
V Engine::sample(int node, double radius) {
    if (node < 0 || node >= int(nodes.size()))
        return {};
    for (int n = 0; n < 8; n++) {
        double t = random() * 6.28318530718;
        V p = nodes[node].at + V{std::cos(t), std::sin(t)} * (std::sqrt(random()) * radius);
        if (clear(nodes[node].at, p))
            return p;
    }
    return nodes[node].at;
}
double Engine::travel_distance(Animal const &a, double time) const {
    double t = std::max(0.0, time - a.route_started);
    double distance = t * a.route_speed;
    if (a.route_relax > 0)
        distance +=
            (a.route_initial_speed - a.route_speed) * a.route_relax * (1 - std::exp(-t / a.route_relax));
    return clamp(distance, 0, a.route_length);
}
double Engine::swimming_speed(Animal const &a, double time) const {
    if (a.path.size() < 2 || travel_distance(a, time) >= a.route_length)
        return 0;
    if (a.route_relax <= 0)
        return a.route_speed;
    return a.route_speed + (a.route_initial_speed - a.route_speed) *
                               std::exp(-std::max(0.0, time - a.route_started) / a.route_relax);
}
V Engine::position(Animal const &a, double time) const {
    if (a.path.size() < 2)
        return a.at;
    double distance = travel_distance(a, time);
    auto it = std::lower_bound(a.lengths.begin() + 1, a.lengths.end(), distance);
    size_t i = std::min(size_t(it - a.lengths.begin()), a.path.size() - 1);
    double f = (distance - a.lengths[i - 1]) / std::max(1e-9, a.lengths[i] - a.lengths[i - 1]);
    return a.path[i - 1] + (a.path[i] - a.path[i - 1]) * clamp(f, 0, 1);
}
void Engine::advance(Animal &a, double time) {
    if (time <= a.sync_time)
        return;
    V previous = a.at;
    a.at = position(a, time);
    double dt = std::max(0.0, time - a.sync_time);
    a.sync_time = time;
    if (dt > 0 && (a.at - previous).len2() > 1e-10)
        a.velocity = (a.at - previous) * (1 / dt);
    if (a.velocity.len2() > .0001)
        a.heading = a.velocity.unit();
    double rate = (a.kind == 1 ? .25 : .4);
    a.depth += clamp(a.target_depth - a.depth, -rate * dt, rate * dt);
    a.depth = clamp(a.depth, 0, std::max(.02, a.bottom - .02));
}
void Engine::route(Animal &a, V goal, int target_node, double speed) {
    auto begin = Clock::now();
    ++route_count;
    V start = a.at;
    a.path.clear();
    a.lengths.clear();
    a.path.push_back(start);
    bool coastal = a.kind == 1 && !a.individual && a.species != 0 && (goal - start).len() > 60;
    if (!coastal && clear(start, goal))
        a.path.push_back(goal);
    else {
        int from = nearest(start, a.node >= 0 ? nodes[a.node].component : -1);
        int to = target_node >= 0 ? target_node : nearest(goal, from >= 0 ? nodes[from].component : -1);
        if (from >= 0 && to >= 0 && nodes[from].component == nodes[to].component) {
            ++search_stamp;
            if (search_stamp == 0) {
                std::fill(visited.begin(), visited.end(), 0);
                ++search_stamp;
            }
            using Q = std::pair<double, int>;
            std::priority_queue<Q, std::vector<Q>, std::greater<Q>> q;
            visited[from] = search_stamp;
            costs[from] = 0;
            parents[from] = -1;
            q.push({0, from});
            int expanded = 0;
            while (!q.empty() && expanded++ < 12000) {
                int n = q.top().second;
                q.pop();
                if (n == to)
                    break;
                for (int next : nodes[n].neighbors) {
                    if (next < 0 || next >= int(nodes.size()))
                        continue;
                    double penalty = coastal ? 1 + std::min(4.0, nodes[next].shore / 180) +
                                                   std::max(0.0, nodes[next].depth - 4) * .4
                                             : 1;
                    double c = costs[n] + (nodes[n].at - nodes[next].at).len() * penalty;
                    if (visited[next] != search_stamp || c < costs[next]) {
                        visited[next] = search_stamp;
                        costs[next] = c;
                        parents[next] = n;
                        q.push({c + (nodes[next].at - nodes[to].at).len(), next});
                    }
                }
            }
            if (visited[to] == search_stamp) {
                std::vector<int> reversed;
                for (int n = to; n >= 0; n = parents[n]) {
                    reversed.push_back(n);
                    if (n == from)
                        break;
                }
                if (!reversed.empty() && reversed.back() == from) {
                    for (auto it = reversed.rbegin(); it != reversed.rend(); ++it)
                        a.path.push_back(nodes[*it].at);
                    if (clear(a.path.back(), goal))
                        a.path.push_back(goal);
                }
            }
        }
    }
    a.lengths.push_back(0);
    for (size_t i = 1; i < a.path.size(); i++)
        a.lengths.push_back(a.lengths.back() + (a.path[i] - a.path[i - 1]).len());
    a.route_length = a.lengths.back();
    a.route_started = sim;
    a.route_speed = std::max(0.0, speed);
    a.route_initial_speed = a.route_speed;
    a.route_relax = 0;
    if (a.path.size() > 1 && (a.path[1] - start).len2() > .0001)
        a.heading = (a.path[1] - start).unit();
    nav_total += seconds(Clock::now() - begin) * 1000;
}
void Engine::remove_occupancy(uint32_t slot) {
    auto &a = animals[slot];
    for (auto k : a.cells) {
        auto it = spatial.find(k);
        if (it == spatial.end())
            continue;
        auto &list = it->second;
        auto found = std::find(list.begin(), list.end(), slot);
        if (found != list.end()) {
            *found = list.back();
            list.pop_back();
        }
        if (list.empty())
            spatial.erase(it);
    }
    a.cells.clear();
}
void Engine::occupancy(uint32_t slot) {
    auto &a = animals[slot];
    V lo = a.at, hi = a.at;
    double horizon = interval(a.tier);
    if (a.target.slot != UINT32_MAX)
        horizon = std::min(horizon, 2.0);
    V end = position(a, sim + horizon);
    lo = {std::min(lo.x, end.x), std::min(lo.y, end.y)};
    hi = {std::max(hi.x, end.x), std::max(hi.y, end.y)};
    double limit = travel_distance(a, sim + horizon);
    for (size_t i = 0; i < a.path.size(); i++) {
        if (i && a.lengths[i - 1] > limit)
            break;
        if (a.lengths[i] + 1e-6 < travel_distance(a, sim))
            continue;
        lo = {std::min(lo.x, a.path[i].x), std::min(lo.y, a.path[i].y)};
        hi = {std::max(hi.x, a.path[i].x), std::max(hi.y, a.path[i].y)};
    }
    int x0 = int(std::floor(lo.x / 128)), y0 = int(std::floor(lo.y / 128)), x1 = int(std::floor(hi.x / 128)),
        y1 = int(std::floor(hi.y / 128));
    if (a.cells.size() == size_t((x1 - x0 + 1) * (y1 - y0 + 1)) && !a.cells.empty() &&
        a.cells.front() == key(x0, y0) && a.cells.back() == key(x1, y1))
        return;
    remove_occupancy(slot);
    for (int y = y0; y <= y1; y++)
        for (int x = x0; x <= x1; x++) {
            auto k = key(x, y);
            spatial[k].push_back(slot);
            a.cells.push_back(k);
        }
}
void Engine::query(V at, double radius, std::vector<uint32_t> &result) {
    result.clear();
    ++query_count;
    if (++query_stamp == 0) {
        std::fill(query_marks.begin(), query_marks.end(), 0);
        ++query_stamp;
    }
    int x0 = int(std::floor((at.x - radius) / 128)), x1 = int(std::floor((at.x + radius) / 128)),
        y0 = int(std::floor((at.y - radius) / 128)), y1 = int(std::floor((at.y + radius) / 128));
    for (int y = y0; y <= y1; y++)
        for (int x = x0; x <= x1; x++) {
            auto it = spatial.find(key(x, y));
            if (it == spatial.end())
                continue;
            for (auto slot : it->second) {
                if (query_marks[slot] == query_stamp)
                    continue;
                query_marks[slot] = query_stamp;
                if (animals[slot].alive && (position(animals[slot], sim) - at).len2() <= radius * radius)
                    result.push_back(slot);
            }
        }
}
int Engine::detail(Animal const &a) const {
    if (!controls.lod || code(a) == controls.selected || (a.tier == 0 && a.threat_until > sim))
        return 0;
    V at = position(a, sim);
    double d = std::min((at - controls.boat).len2(), (at - controls.camera).len2());
    if (d < std::pow(controls.detailed + (a.tier == 0 ? controls.hysteresis : 0), 2))
        return 0;
    if (d < std::pow(controls.intermediate + (a.tier < 2 ? controls.hysteresis : 0), 2))
        return 1;
    return 2;
}
double Engine::interval(int tier) const {
    return tier == 0 ? .2 : (tier == 1 ? 2 : 12);
}
void Engine::schedule(uint32_t slot, double at) {
    auto &a = animals[slot];
    a.due = at;
    ++a.token;
    events.push({at, slot, a.generation, a.token});
}
bool Engine::breakaway(Animal const &a) const {
    return a.kind == 1 && !a.individual && prey_modes[a.species] == 1;
}
V Engine::axes(Animal const &a) const {
    if (a.kind != 1 || a.individual)
        return {};
    double radius = clamp(std::sqrt(double(a.quantity)) * .32, .6, 8);
    return {radius * (1 + a.fear * .45), radius * .55};
}
V Engine::prey_point(Animal const &prey, V observer) const {
    V center = position(prey, sim), d = observer - center, shape = axes(prey);
    if (shape.x == 0 || d.len2() < 1e-10)
        return center;
    V h = prey.heading, side{-h.y, h.x};
    double x = d.x * h.x + d.y * h.y, y = d.x * side.x + d.y * side.y;
    double q = std::sqrt(x * x / (shape.x * shape.x) + y * y / (shape.y * shape.y));
    return q <= 1 ? observer : center + d * (1 / q);
}
bool Engine::senses(Animal const &a, Animal const &prey) const {
    V delta = prey_point(prey, a.at) - a.at;
    double d = delta.len(), vertical = std::abs(prey.depth - a.depth);
    if (d * d + vertical * vertical > a.profile.detect * a.profile.detect)
        return false;
    double close = std::min(a.profile.awareness_cap, a.profile.detect * a.profile.awareness);
    if (d * d + vertical * vertical <= close * close)
        return true;
    return d > .0001 && (delta.x * a.heading.x + delta.y * a.heading.y) / d >= a.profile.cone_cos;
}
Handle Engine::acquire(uint32_t slot, bool edible_only) {
    auto const &a = animals[slot];
    thread_local std::vector<uint32_t> candidates;
    query(a.at, a.profile.detect + 12, candidates);
    double best = -1e30;
    Handle chosen;
    for (auto i : candidates) {
        auto const &prey = animals[i];
        if (i == slot || prey.kind == 2 || prey.size >= a.size * a.profile.gape || prey.quantity < 1 ||
            (prey.kind == 0 && prey.species == a.species && prey.size > a.size * .3))
            continue;
        if (a.profile.style == 3 && prey.kind != 3 &&
            !(prey.kind == 1 && (prey.species == 4 || prey.species == 5)))
            continue;
        if (edible_only && breakaway(prey))
            continue;
        if (!senses(a, prey))
            continue;
        V point = prey_point(prey, a.at);
        if (!clear(a.at, point))
            continue;
        int rank = breakaway(prey) ? 0 : (prey.kind == 1 && !prey.individual ? 1 : (prey.kind == 1 ? 3 : 2));
        double score = rank * 10000 - (point - a.at).len() + std::min(5.0, prey.size * .1) + prey.fear;
        if (score > best) {
            best = score;
            chosen = handle(i);
        }
    }
    return chosen;
}
void Engine::shelter(Animal &a) {
    a.hunger = 0;
    if (a.node < 0)
        a.node = nearest(a.at);
    if (a.node < 0) {
        a.decision = sim + 30;
        return;
    }
    if (a.path.size() > 1 && (position(a, sim) - a.path.back()).len() > 1) {
        a.state = a.individual ? 14 : 13;
        a.decision =
            sim + std::max(1.0, (a.route_length - travel_distance(a, sim)) / std::max(.05, a.route_speed));
        return;
    }
    if (a.shelter_hold == 0) {
        a.shelter_hold = sim + 6 + random() * 20;
        a.decision = a.shelter_hold;
        a.state = a.individual ? 14 : 15;
        return;
    }
    a.shelter_hold = 0;
    int best = a.node, cursor = a.node;
    double score = -1e9;
    double max_distance = a.individual ? 100 : 650;
    for (int k = 0; k < 28; k++) {
        auto const &neighbors = nodes[cursor].neighbors;
        if (!neighbors.empty())
            cursor = neighbors[size_t(random() * neighbors.size()) % neighbors.size()];
        auto const &n = nodes[cursor];
        double distance = (n.at - a.at).len();
        if (distance > max_distance || n.component != nodes[a.node].component) {
            cursor = a.node;
            continue;
        }
        double value = n.cover * 3 - std::min(3.0, n.shore / 200) -
                       std::abs(n.depth - std::min(4.0, nodes[a.home >= 0 ? a.home : a.node].depth)) * .25 +
                       random() * .8;
        if (cursor == a.node || cursor == a.feeding)
            value -= .6;
        if (value > score) {
            score = value;
            best = cursor;
        }
    }
    V goal = sample(best, a.individual ? 5 : 15);
    route(a, goal, best, a.species == 4 || a.species == 5 ? .08 : (a.individual ? .25 : .45));
    a.feeding = best;
    a.state = a.individual ? 14 : 13;
    a.decision = sim + std::max(2.0, a.route_length / std::max(.05, a.route_speed));
}
void Engine::plan(Animal &a) {
    if (a.kind == 1) {
        shelter(a);
        return;
    }
    if (a.node < 0)
        a.node = nearest(a.at);
    if (a.node < 0)
        return;
    int destination = a.node;
    bool ambush = a.profile.style == 1 || a.profile.style == 2;
    bool rock = a.kind == 0 && a.species == 7 && a.size >= 43.18;
    if (a.kind != 1 && (a.energy < .2 || (!a.motivated && ambush))) {
        a.state = 9;
        destination = a.home >= 0 ? a.home : a.node;
    } else if (rock) {
        destination = a.home >= 0 ? a.home : a.node;
        a.state = 4;
    } else {
        double best = -1e9;
        std::vector<int> options = nodes[a.node].neighbors;
        options.push_back(a.node);
        if (a.feeding >= 0 && nodes[a.feeding].component == nodes[a.node].component)
            options.push_back(a.feeding);
        if (a.home >= 0 && nodes[a.home].component == nodes[a.node].component)
            options.push_back(a.home);
        for (int n : options) {
            nodes[n].food = std::min(1.0, nodes[n].food + (sim - nodes[n].food_time) * .0001);
            nodes[n].food_time = sim;
            double score = nodes[n].food + nodes[n].cover * (ambush ? .8 : .2) + random() * .55 -
                           std::abs(nodes[n].depth - a.holding) * .04;
            if (n == a.feeding)
                score += .15;
            if (!ambush) {
                V ahead = (nodes[n].at - a.at).unit();
                score += (ahead.x * a.heading.x + ahead.y * a.heading.y) * .4;
                if (n == a.previous_patrol_node)
                    score -= .8;
                if (n == a.node)
                    score -= .35;
            }
            if (score > best) {
                best = score;
                destination = n;
            }
        }
        a.state = ambush ? 4 : 0;
    }
    V goal = rock ? a.home_at + V{random() * 12 - 6, random() * 12 - 6}
                  : sample(destination, a.kind == 1 ? 18 : 35);
    if (rock && !clear(nodes[destination].at, goal))
        goal = sample(destination, 8);
    if (a.kind == 0 && a.school >= 0 && !rock && a.state != 9) {
        auto &shared = schools[a.school];
        if (shared.until <= sim || shared.node < 0) {
            shared.goal = goal;
            shared.node = destination;
            shared.until = sim + 20 + random() * 15;
        } else if (nodes[shared.node].component == nodes[a.node].component) {
            V offset{std::sin(double(a.id) * 12.9898) * 3, std::sin(double(a.id) * 78.233) * 3};
            V member = shared.goal + offset;
            if (clear(shared.goal, member)) {
                goal = member;
                destination = shared.node;
            }
        }
    }
    double velocity = a.kind == 1 ? (a.species == 4 || a.species == 5 ? .05 : .4) : a.profile.cruise;
    if (a.state == 9)
        velocity *= .35;
    route(a, goal, destination, velocity);
    a.decision = sim + (a.kind == 1 ? 45 : (ambush ? 35 : 25)) + random() * 35;
    a.previous_patrol_node = a.node;
    a.feeding = destination;
}
void Engine::steer(Animal &a, V goal, double dt, double speed) {
    V wanted = (goal - a.at).unit() * speed;
    double acceleration = (a.kind == 1 ? 2.5 : 1.8) * dt;
    V change = wanted - a.velocity;
    if (change.len() > acceleration)
        change = change.unit() * acceleration;
    a.velocity = a.velocity + change;
    V next = a.at + a.velocity * .2;
    if (clear(a.at, next)) {
        route(a, next, -1, a.velocity.len());
    } else if (a.path.size() < 2 || sim > a.route_started + a.route_length / std::max(.1, a.route_speed))
        route(a, goal, -1, speed);
}
void Engine::retire(uint32_t slot) {
    auto &a = animals[slot];
    if (!a.alive)
        return;
    advance(a, sim);
    a.path.clear();
    a.velocity = {};
    a.alive = false;
    a.quantity = 0;
    ++a.token;
    remove_occupancy(slot);
    if (a.kind == 1) {
        bait_ids.erase(a.id);
        if (a.temporary) {
            auto it = bait_ids.find(a.parent_id);
            if (it != bait_ids.end())
                animals[it->second].escapees = std::max(0, animals[it->second].escapees - 1);
        }
        free_bait.push_back(slot);
    }
    a.event = 4;
}
bool Engine::eat(uint32_t slot) {
    auto &a = animals[slot];
    if (!a.alive || a.quantity <= 0 || breakaway(a))
        return false;
    --a.quantity;
    ++consumed;
    if (a.quantity == 0 && a.kind != 3)
        retire(slot);
    if (a.node >= 0)
        nodes[a.node].food = std::max(0.0, nodes[a.node].food - .002);
    return true;
}
uint32_t Engine::add_bait(Animal a) {
    uint32_t slot;
    int index;
    auto free = std::find_if(free_bait.rbegin(), free_bait.rend(),
                             [&](uint32_t i) { return code(animals[i]) != controls.selected; });
    if (free != free_bait.rend()) {
        slot = *free;
        free_bait.erase(std::next(free).base());
        index = animals[slot].index;
        a.generation = animals[slot].generation + 1;
        animals[slot] = std::move(a);
    } else {
        index = next_bait_index;
        if (index >= bait_limit)
            return UINT32_MAX;
        ++next_bait_index;
        slot = uint32_t(animals.size());
        animals.push_back(std::move(a));
        query_marks.push_back(0);
    }
    auto &item = animals[slot];
    item.kind = 1;
    item.index = index;
    item.id = next_bait_id++;
    item.alive = true;
    item.last = sim;
    item.sync_time = sim;
    item.path.clear();
    item.cells.clear();
    item.token = 0;
    item.tier = detail(item);
    bait_ids[item.id] = slot;
    code_slots[code(item)] = slot;
    occupancy(slot);
    schedule(slot, sim + .2);
    return slot;
}
void Engine::scatter(uint32_t slot, V threat) {
    auto &a = animals[slot];
    if (!a.alive)
        return;
    advance(a, sim);
    V away = (a.at - threat).unit();
    if (away.len2() < .01)
        away = a.heading;
    // Shared reaction heading persists across attackers instead of reversing every event.
    if (a.threat_until <= sim || sim >= a.reaction_at) {
        a.escape_heading = (a.escape_heading * .6 + away * .4).unit();
        a.threat = threat;
        a.reaction_at = sim + 3;
        a.decision = sim;
    }
    a.threat_until = sim + 3;
    a.fear = std::min(1.0, a.fear + .15);
    a.spread = std::min(.6, a.spread + .08);
    a.event = 2;
    if (a.due > sim + std::min(1.0, interval(a.tier)))
        schedule(slot, sim + std::min(1.0, interval(a.tier)));
    if (!breakaway(a) || sim < a.scatter_at || (prey_point(a, threat) - threat).len() > pressure_range)
        return;
    a.scatter_at = sim + detach_interval;
    int count = a.quantity < 12 ? 1 : detach_min + int(random() * (detach_max - detach_min + 1));
    for (int n = 0; n < count && a.escapees < escape_cap && a.quantity > 0; n++) {
        Animal child = a;
        child.temporary = child.individual = true;
        child.parent_id = a.id;
        child.quantity = child.capacity = 1;
        child.escapees = 0;
        child.target = {};
        child.hunger = 0;
        child.state = 10;
        child.detached_at = sim;
        child.regroup_at = sim + 2;
        child.spread = 0;
        V edge = prey_point(a, threat);
        V offset{random() * 2 - 1, random() * 2 - 1};
        if (clear(a.at, edge + offset))
            child.at = edge + offset;
        child.depth = clamp(a.depth + (random() - .5) * .3, 0, a.bottom - .02);
        uint32_t added = add_bait(std::move(child));
        if (added == UINT32_MAX)
            break;
        --a.quantity;
        ++a.escapees;
        ++detached;
    }
}
void Engine::attack(uint32_t slot) {
    auto &a = animals[slot];
    if (!valid(a.target))
        return;
    auto &prey = animals[a.target.slot];
    advance(prey, sim);
    if (breakaway(prey))
        return; // A school is pressure, never a meal.
    double vertical = std::abs(a.depth - prey.depth), distance = (a.at - prey_point(prey, a.at)).len();
    if (distance > a.profile.reach || vertical > a.profile.reach || sim < a.attack_at)
        return;
    ++a.attempts;
    a.attack_at = sim + a.profile.cooldown;
    a.energy = std::max(0.0, a.energy - .025);
    bool ambush = a.profile.style == 1 || a.profile.style == 2;
    double chance = a.profile.chance + (ambush ? .22 : .06) * (1 - prey.fear) +
                    energy_weight * (a.energy - .5) + .12 * (.35 - prey.size / std::max(1.0, a.size)) -
                    cover_weight * (prey.node >= 0 ? nodes[prey.node].cover : .1) - .10 * prey.fear -
                    .06 * clamp(prey.velocity.len() / std::max(.1, a.profile.burst), 0, 1) +
                    std::min(.12, (sim - a.pursuit_started) * .003) -
                    .10 * vertical / std::max(.1, a.profile.reach);
    chance = clamp(chance, hit_min, hit_max);
    if (random() < chance && eat(a.target.slot)) {
        ++a.captures;
        a.state = 8;
        a.until = sim + a.profile.consume;
        a.hunger = std::max(0.0, a.hunger - clamp(meal_base + prey.size / std::max(1.0, a.size) * meal_ratio,
                                                  meal_min, meal_max));
        if (a.hunger <= hunt_stop)
            a.motivated = false;
        a.last_capture = sim;
        a.recover_until = a.until + post_meal_seconds;
        a.event = 1;
        if (a.kind == 0 && a.species == 7)
            a.return_home = true;
        if (a.kind == 0)
            a.size += std::min(.02, prey.size * .002);
        if (prey.alive)
            scatter(a.target.slot, a.at);
        a.target = {};
        feeding_glide(a);
    } else {
        ++a.misses;
        a.energy = std::max(0.0, a.energy - .035);
        a.event = 3;
        scatter(a.target.slot, a.at);
    }
}
void Engine::feeding_glide(Animal &a) {
    // One route per meal; analytic deceleration works at every simulation tier.
    double initial = swimming_speed(a, sim);
    double slow = a.profile.cruise * a.profile.feeding_fraction;
    double relax = a.profile.feeding_mode == 3 ? .3 : .8;
    double duration = std::max(1.0, a.recover_until - sim + 2);
    V direction = a.heading;
    V holding = a.home_at;
    if (a.profile.feeding_mode == 2 && a.school >= 0) {
        auto school = schools.find(a.school);
        if (school != schools.end())
            holding = school->second.goal;
    }
    if (a.profile.feeding_mode == 1 || a.profile.feeding_mode == 2) {
        V toward = (holding - a.at).unit();
        if (toward.len2() > .01)
            direction = (a.heading * .65 + toward * .35).unit();
    }
    double length = std::max(.3, slow * duration + std::max(0.0, initial - slow) * relax);
    V goal = a.at + direction * length;
    if (!clear(a.at, goal)) {
        // Turn locally before asking the graph; never keep a chase route through a meal.
        V side{-direction.y, direction.x};
        goal = a.at + side * length;
        if (!clear(a.at, goal))
            goal = a.at - side * length;
        if (!clear(a.at, goal))
            goal = a.node >= 0 ? nodes[a.node].at : a.at;
    }
    route(a, goal, -1, slow);
    a.route_initial_speed = std::max(initial, slow);
    a.route_relax = relax;
    a.decision = a.recover_until;
    a.detect_at = std::max(a.detect_at, a.recover_until);
    a.target_depth = a.holding;
}
void Engine::relaxed_patrol(uint32_t slot) {
    auto &a = animals[slot];
    if (sim < a.decision)
        return;
    double cadence = a.tier == 0 ? 8 : (a.tier == 1 ? 12 : 20);
    if (valid(a.nearby_food)) {
        auto const &food = animals[a.nearby_food.slot];
        if (!senses(a, food) || !clear(a.at, prey_point(food, a.at)))
            a.nearby_food = {};
    }
    if (!valid(a.nearby_food))
        a.nearby_food = acquire(slot);
    if (valid(a.nearby_food)) {
        auto const &food = animals[a.nearby_food.slot];
        V center = position(food, sim);
        double spacing = axes(food).x + pressure_range + 5;
        V away = (a.at - center).unit();
        if (away.len2() < .01)
            away = {-food.heading.y, food.heading.x};
        V goal;
        if ((center - a.at).len() > spacing + 8)
            goal = center + away * spacing + food.heading * 5;
        else {
            V forward = food.velocity.len2() > .01 ? food.heading : a.heading;
            goal = a.at + forward * std::max(6.0, a.profile.cruise * cadence * .65);
            if ((center - a.at).len() < spacing)
                goal = goal + away * (spacing - (center - a.at).len());
        }
        if (clear(a.at, goal)) {
            route(a, goal, -1, a.profile.cruise * .65);
            a.state = 16;
            a.decision = sim + cadence;
            return; // Proximity interest is not a hunt target and never emits pressure.
        }
        a.nearby_food = {};
    }
    // Finish a useful route before choosing another, instead of oscillating around home.
    if (a.path.size() > 1 && travel_distance(a, sim) + 1 < a.route_length) {
        a.state = 0;
        a.decision = sim + cadence;
        return;
    }
    plan(a);
}
void Engine::hunt(uint32_t slot, double dt) {
    auto &a = animals[slot];
    bool ambush = a.profile.style == 1 || a.profile.style == 2;
    if (a.threat_until > sim) {
        a.state = 10;
        V goal = a.at + (a.at - a.threat).unit() * 12;
        if (a.tier == 0)
            steer(a, goal, dt, a.profile.burst);
        else
            route(a, goal, -1, a.profile.burst);
        a.target = {};
        return;
    }
    if (sim < a.recover_until) {
        a.state = sim < a.until ? 8 : 9;
        a.target = {};
        a.energy = std::min(1.0, a.energy + dt * .005);
        return; // The meal route keeps advancing analytically; no new attacks.
    }
    if (a.return_home) {
        if ((a.at - a.home_at).len() > 2) {
            if (a.path.empty() || sim >= a.decision) {
                route(a, a.home_at, a.home, a.profile.cruise);
                a.decision = sim + 5;
            }
            a.state = 9;
            return;
        }
        a.return_home = false;
    }
    if (a.energy < .15) {
        a.state = 9;
        a.target = {};
        a.nearby_food = {};
        a.energy = std::min(1.0, a.energy + dt * .025);
        if (sim >= a.decision)
            plan(a);
        return;
    }
    if (!a.motivated) {
        a.target = {};
        a.energy = std::min(1.0, a.energy + dt * .005);
        if (ambush) {
            // Concealed holding is intentional; being satisfied is not exhaustion.
            a.state = 4;
            a.path.clear();
            a.velocity = {};
        } else
            relaxed_patrol(slot);
        return;
    }
    a.nearby_food = {};
    if (valid(a.target) && breakaway(animals[a.target.slot]) && sim >= a.detect_at) {
        a.detect_at = sim + (a.tier == 0 ? .5 : 2);
        Handle exposed = acquire(slot, true);
        if (valid(exposed)) {
            a.target = exposed;
            a.ambush_committed = false;
            a.pursuit_started = a.tracked_at = sim;
        }
    }
    if (valid(a.target)) {
        auto &prey = animals[a.target.slot];
        V target = prey_point(prey, a.at);
        double distance = (target - a.at).len();
        if (distance <= a.profile.detect * 1.25 && clear(a.at, target))
            a.tracked_at = sim;
        if (sim - a.tracked_at > 6 || distance > a.profile.detect * 2 ||
            sim - a.pursuit_started > (breakaway(prey) ? 22 : 60)) {
            a.target = {};
            a.detect_at = sim + 3;
            a.decision = sim;
            return;
        }
        if (a.kind == 0 && a.species == 7 && a.size >= 43.18 && (a.at - a.home_at).len() > 25) {
            a.target = {};
            route(a, a.home_at, a.home, a.profile.cruise);
            a.detect_at = sim + 4;
            return;
        }
        a.target_depth = clamp(prey.depth, 0, a.bottom - .02);
        bool pressure = breakaway(prey);
        if (ambush && !a.ambush_committed && distance > a.profile.lunge) {
            a.state = 4;
            a.path.clear();
            a.velocity = {};
            return; // A concealed predator does not frighten approaching bait.
        }
        a.ambush_committed = true;
        a.state = 3;
        if (distance <= pressure_range && std::abs(a.depth - prey.depth) < 2)
            scatter(a.target.slot, a.at);
        if (a.tier == 0) {
            V intercept =
                target + prey.velocity * std::min(2.0, distance / std::max(.1, a.profile.burst) * .4);
            if (!clear(target, intercept))
                intercept = target;
            steer(a, intercept, dt, a.profile.burst);
        } else if (sim >= a.decision) {
            route(a, target + prey.velocity * std::min(3.0, distance / std::max(.1, a.profile.burst)), -1,
                  a.profile.burst);
            a.decision = sim + 2;
        }
        if (pressure)
            a.state = 12;
        a.energy = std::max(0.0, a.energy - dt * .0015);
        if (!pressure)
            attack(slot);
        return;
    }
    a.target = {};
    if (sim >= a.detect_at) {
        a.detect_at = sim + (a.tier == 0 ? 1 : (a.tier == 1 ? 5 : 20));
        Handle chosen = acquire(slot);
        if (valid(chosen)) {
            a.target = chosen;
            a.ambush_committed = false;
            if (ambush) {
                a.path.clear();
                a.velocity = {};
            }
            a.pursuit_started = a.tracked_at = sim;
            a.state = ambush ? 4 : 2;
            a.event = 5;
            return;
        }
    }
    a.energy = std::min(1.0, a.energy + dt * .002);
    if (sim >= a.decision || a.path.empty())
        plan(a);
}
void Engine::bait(uint32_t slot, double dt) {
    auto &a = animals[slot];
    if (a.quantity == 0 && a.escapees == 0) {
        retire(slot);
        return;
    }
    a.hunger = 0;
    a.fear = std::max(0.0, a.fear - dt * .08);
    a.spread = std::max(.05, a.spread - dt * .02);
    if (a.temporary || a.individual) {
        a.hunger = 0;
        if (a.threat_until > sim) {
            a.state = 10;
            a.regroup_at = sim + 2;
            V goal = a.at + a.escape_heading * 12 +
                     V{std::sin(sim * .7 + a.id) * .8, std::cos(sim * .7 + a.id) * .8};
            a.target_depth = clamp(a.depth + (random() - .5), 0, a.bottom - .02);
            if (a.tier == 0)
                steer(a, goal, dt, 1.3);
            else if (sim >= a.decision) {
                route(a, goal, -1, 1.3);
                a.decision = sim + 3;
            }
            return;
        }
        if (sim < a.regroup_at)
            return;
        auto parent = bait_ids.find(a.parent_id);
        uint32_t parent_slot = parent == bait_ids.end() ? UINT32_MAX : parent->second;
        if (parent_slot != UINT32_MAX &&
            (!animals[parent_slot].alive || animals[parent_slot].individual ||
             (position(animals[parent_slot], sim) - a.at).len() > 600 ||
             (a.node >= 0 && animals[parent_slot].node >= 0 &&
              nodes[a.node].component != nodes[animals[parent_slot].node].component))) {
            if (a.temporary)
                animals[parent_slot].escapees = std::max(0, animals[parent_slot].escapees - 1);
            parent_slot = UINT32_MAX;
            a.parent_id = 0;
        }
        if (parent_slot == UINT32_MAX && sim >= a.detect_at) {
            a.detect_at = sim + 10;
            thread_local std::vector<uint32_t> nearby;
            query(a.at, 100, nearby);
            double closest = 1e9;
            for (auto i : nearby) {
                auto const &b = animals[i];
                if (b.kind != 1 || b.individual || b.species != a.species || !clear(a.at, position(b, sim)))
                    continue;
                double d = (position(b, sim) - a.at).len2();
                if (d < closest) {
                    closest = d;
                    parent_slot = i;
                }
            }
            if (parent_slot != UINT32_MAX) {
                a.parent_id = animals[parent_slot].id;
                if (a.temporary)
                    ++animals[parent_slot].escapees;
            }
        }
        if (parent_slot != UINT32_MAX && animals[parent_slot].alive) {
            auto &parent_school = animals[parent_slot];
            V goal = position(parent_school, sim);
            a.state = 11;
            a.target_depth = parent_school.depth;
            if ((goal - a.at).len() < 3 && std::abs(a.depth - parent_school.depth) < .6 &&
                parent_school.threat_until <= sim) {
                ++parent_school.quantity;
                parent_school.capacity = std::max(parent_school.capacity, parent_school.quantity);
                ++rejoined;
                retire(slot);
                return;
            }
            if (a.tier == 0)
                steer(a, goal, dt, .8);
            else if (sim >= a.decision || a.path.empty() || (a.path.back() - goal).len() > 12) {
                route(a, goal, parent_school.node, .8);
                a.decision = sim + 5;
            }
        } else {
            a.state = 14;
            if (sim >= a.decision)
                shelter(a);
        }
        return;
    }
    if (a.threat_until > sim) {
        a.state = 10;
        if (sim >= a.decision) {
            V goal = a.at + a.escape_heading * 30;
            if (!clear(a.at, goal)) {
                V side{-a.escape_heading.y, a.escape_heading.x};
                goal = a.at + side * 12;
                if (!clear(a.at, goal))
                    goal = a.at - side * 12;
            }
            route(a, goal, -1, .7 + a.fear * .6);
            a.decision = sim + 4;
        }
        return;
    }
    a.state = a.path.size() > 1 && (position(a, sim) - a.path.back()).len() > 1 ? 13 : 15;
    a.recruitment += dt * .02;
    int births = std::min(int(a.recruitment), std::max(0, a.capacity - a.quantity - a.escapees));
    a.quantity += births;
    created += births;
    a.recruitment -= std::floor(a.recruitment);
    if (sim >= a.merge_at && a.escapees == 0 && a.fear < .1) {
        a.merge_at = sim + 60;
        thread_local std::vector<uint32_t> near;
        query(a.at, 8, near);
        for (auto i : near) {
            auto &other = animals[i];
            if (i <= slot || other.kind != 1 || other.individual || other.species != a.species ||
                other.escapees || other.fear > .1 || other.quantity + a.quantity > 160)
                continue;
            if (!clear(a.at, position(other, sim)))
                continue;
            a.quantity += other.quantity;
            a.capacity += other.capacity;
            retire(i);
            break;
        }
    }
    if (sim >= a.decision)
        shelter(a);
}
void Engine::update(uint32_t slot) {
    auto &a = animals[slot];
    if (!a.alive)
        return;
    double dt = std::max(0.0, sim - a.last);
    advance(a, sim);
    a.tier = detail(a);
    if (a.node < 0 || (a.at - nodes[a.node].at).len() > 100) {
        int n = nearest(a.at, a.node >= 0 ? nodes[a.node].component : -1);
        if (n >= 0) {
            a.node = n;
            a.zone = nodes[n].zone;
        }
    }
    a.bottom = std::max(.1, (a.node >= 0 ? nodes[a.node].depth : 2) + controls.tide);
    double ratio =
        a.kind == 1 ? (a.species == 4 || a.species == 5 ? .95 : (a.species == 0 ? .15 : .45))
                    : (a.kind == 2 ? (a.species == 2 ? .9 : (a.species == 3 ? .35 : .6))
                                   : (a.species == 3 || a.species == 6 ? .94 : (a.species == 0 ? .8 : .5)));
    a.holding = clamp(a.bottom * ratio + std::sin(sim * .015 + double(a.id % 1000)) * .15, 0, a.bottom - .02);
    if (!valid(a.target))
        a.target_depth = a.holding;
    if (a.kind == 3) {
        int births = std::min(a.capacity - a.quantity, int(dt * .1));
        a.quantity += births;
        created += births;
    } else if (a.kind == 1)
        bait(slot, dt);
    else {
        double activity = (a.state == 3 || a.state == 12 || a.state == 10) ? pursuit_hunger_factor : 1;
        a.hunger = clamp(a.hunger + dt * hunger_rate * a.profile.hunger_factor * activity *
                                        clamp(60 / std::max(20.0, a.size), .5, 1.5),
                         0, 1);
        if (a.hunger >= hunt_start)
            a.motivated = true;
        else if (a.hunger <= hunt_stop)
            a.motivated = false;
        auto hunting_begin = Clock::now();
        hunt(slot, dt);
        hunting_total += seconds(Clock::now() - hunting_begin) * 1000;
    }
    a.last = sim;
    if (!a.alive)
        return;
    occupancy(slot);
    double delay = a.kind == 3 ? 30 : interval(a.tier);
    if (a.kind == 1 && (a.temporary || a.threat_until > sim))
        delay = std::min(delay, 3.0);
    if (valid(a.target) && a.tier > 0)
        delay = std::min(delay, 3.0);
    // Do not stretch short consumption/recovery phases to a twelve-second background tick.
    for (double boundary : {a.until, a.recover_until})
        if (boundary > sim + .01)
            delay = std::min(delay, boundary - sim);
    if (a.path.size() > 1 && a.route_speed > 0) {
        double arrival = a.route_started + a.route_length / a.route_speed;
        if (arrival > sim + .01)
            delay = std::min(delay, arrival - sim);
    }
    if (a.tier > 0) {
        double distance = std::min((a.at - controls.boat).len(), (a.at - controls.camera).len()),
               boundary = a.tier == 2 ? controls.intermediate : controls.detailed;
        if (a.route_speed > 0)
            delay = std::min(delay, std::max(.2, (distance - boundary) / a.route_speed));
    }
    schedule(slot, sim + std::max(.1, delay));
    ++event_count;
}
void Engine::start(uint64_t seed) {
    stop();
    rng.seed(seed);
    stopping = false;
    animals.reserve(animals.size() + bait_limit);
    query_marks.resize(animals.size());
    costs.resize(nodes.size());
    parents.resize(nodes.size());
    visited.resize(nodes.size());
    for (uint32_t i = 0; i < nodes.size(); i++)
        node_cells[key(int(std::floor(nodes[i].at.x / 256)), int(std::floor(nodes[i].at.y / 256)))].push_back(
            i);
    for (uint32_t i = 0; i < animals.size(); i++) {
        auto &a = animals[i];
        code_slots[code(a)] = i;
        if (a.alive)
            initial_units += a.quantity;
        if (a.kind == 1) {
            bait_ids[a.id] = i;
            next_bait_id = std::max(next_bait_id, a.id + 1);
            next_bait_index = std::max(next_bait_index, a.index + 1);
        }
        a.node = nearest(a.at);
        if (a.node >= 0) {
            a.zone = nodes[a.node].zone;
            a.bottom = nodes[a.node].depth;
        }
        a.motivated = a.hunger >= hunt_start;
        a.home_at = a.at;
        double angle = random() * 6.28318530718;
        a.heading = {std::cos(angle), std::sin(angle)};
        a.tier = detail(a);
        occupancy(i);
        schedule(i, .1 + random() * interval(a.tier));
    }
    publish();
    worker = std::thread(&Engine::loop, this);
}
void Engine::stop() {
    stopping = true;
    cv.notify_all();
    if (worker.joinable())
        worker.join();
}
void Engine::control(Controls const &c) {
    {
        std::lock_guard<std::mutex> lock(mutex);
        requested_controls = c;
    }
    cv.notify_all();
}
void Engine::spawn(int species, V at) {
    {
        std::lock_guard<std::mutex> lock(mutex);
        commands.push_back({0, species, at});
    }
    cv.notify_all();
}
void Engine::publish() {
    auto snap = std::make_shared<Snapshot>();
    snap->rows.reserve(animals.size());
    snap->time = sim;
    snap->requested = requested;
    snap->cpu_ms = cpu_total;
    snap->wall = wall_total;
    snap->achieved = wall_total > 0 ? sim / wall_total : 0;
    snap->events = event_count;
    snap->consumed = consumed;
    snap->initial_units = initial_units;
    snap->created = created;
    snap->detached = detached;
    snap->rejoined = rejoined;
    snap->queries = query_count;
    snap->routes = route_count;
    snap->nav_ms = nav_total;
    snap->hunting_ms = hunting_total;
    snap->memory = animals.capacity() * sizeof(Animal) + water.size();
    for (auto const &a : animals) {
        Row r{};
        r.code = code(a);
        r.kind = a.kind;
        r.index = a.index;
        r.id = a.id;
        r.generation = a.generation;
        r.species = a.species;
        r.state = a.state;
        r.tier = a.tier;
        r.zone = a.zone;
        r.school = a.school;
        r.quantity = a.quantity;
        r.escapees = a.escapees;
        r.captures = a.captures;
        r.misses = a.misses;
        r.attempts = a.attempts;
        r.parent_id = a.parent_id;
        r.alive = a.alive;
        r.temporary = a.temporary;
        r.individual = a.individual;
        r.at = position(a, sim);
        r.velocity = a.velocity;
        r.heading = a.heading;
        r.threat = a.threat;
        V shape = axes(a);
        r.major = shape.x;
        r.minor = shape.y;
        r.detect = a.profile.detect;
        r.awareness = std::min(a.profile.awareness_cap, a.profile.detect * a.profile.awareness);
        r.cone_cos = a.profile.cone_cos;
        r.destination = a.path.empty() ? a.at : a.path.back();
        r.depth =
            clamp(a.depth + clamp(a.target_depth - a.depth, -(a.kind == 1 ? .25 : .4) * (sim - a.sync_time),
                                  (a.kind == 1 ? .25 : .4) * (sim - a.sync_time)),
                  0, std::max(.02, a.bottom - .02));
        r.holding = a.holding;
        r.target_depth = a.target_depth;
        r.bottom = a.bottom;
        r.size = a.size;
        r.hunger = a.hunger;
        r.energy = a.energy;
        r.fear = a.fear;
        r.spread = a.spread;
        r.target_code = valid(a.target) ? code(animals[a.target.slot]) : -1;
        r.target_id = valid(a.target) ? animals[a.target.slot].id : 0;
        r.event = a.event;
        r.home = a.home;
        r.feeding = a.feeding;
        r.school_prey = breakaway(a);
        r.motivated = a.motivated;
        r.consume_left = std::max(0.0, a.until - sim);
        r.recover_left = std::max(0.0, a.recover_until - std::max(sim, a.until));
        r.swim_speed = swimming_speed(a, sim);
        r.capture_age = a.last_capture < 0 ? -1 : sim - a.last_capture;
        r.target_slot = valid(a.target) ? int(a.target.slot) : -1;
        r.hunt_eligible = a.alive && (a.kind == 0 || a.kind == 2) && a.motivated && a.hunger > hunt_stop &&
                          a.energy >= .15 && !a.return_home && sim >= a.recover_until &&
                          (a.state == 2 || a.state == 3 || a.state == 4 || a.state == 5 || a.state == 12) &&
                          r.target_slot >= 0 && sim - a.tracked_at <= 6 &&
                          sim - a.pursuit_started <= (breakaway(animals[a.target.slot]) ? 22 : 60);
        snap->rows.push_back(r);
        if (a.alive) {
            ++snap->alive[a.kind];
            if (a.kind == 1) {
                ++snap->bait_counts[a.temporary ? 2 : (a.individual ? 1 : 0)];
                snap->prey_units += a.quantity;
            }
            snap->units += a.quantity;
            if (a.kind < 3)
                ++snap->counts[a.tier];
        }
    }
    for (auto const &a : animals)
        if (a.alive && valid(a.target)) {
            auto &prey = animals[a.target.slot];
            ++snap->rows[a.target.slot].targeters;
            if (prey.temporary) {
                auto parent = bait_ids.find(prey.parent_id);
                if (parent != bait_ids.end())
                    ++snap->rows[parent->second].child_targeters;
            }
        }
    std::atomic_store(&published, std::shared_ptr<const Snapshot>(snap));
}
void Engine::loop() {
    auto last = Clock::now(), published_at = last;
    V previous_boat{INFINITY, INFINITY}, previous_camera = previous_boat;
    int previous_selected = -2;
    while (!stopping) {
        auto now = Clock::now();
        double wall = seconds(now - last);
        last = now;
        wall_total += wall;
        std::vector<Command> batch;
        {
            std::lock_guard<std::mutex> lock(mutex);
            controls = requested_controls;
            batch.swap(commands);
        }
        requested += wall * std::max(0.0, controls.speed);
        auto begin = Clock::now();
        for (auto cmd : batch) {
            if (!wet(cmd.at))
                continue;
            Animal a;
            a.kind = 1;
            a.species = cmd.species;
            a.individual = true;
            a.hunger = 0;
            a.at = cmd.at;
            a.node = nearest(a.at);
            a.home = a.feeding = a.node;
            a.size = cmd.species == 5 ? 3 : 6;
            a.depth = .5;
            if (add_bait(std::move(a)) != UINT32_MAX)
                ++created;
        }
        if ((controls.boat - previous_boat).len2() > 2500 ||
            (controls.camera - previous_camera).len2() > 2500 || controls.selected != previous_selected) {
            previous_boat = controls.boat;
            previous_camera = controls.camera;
            previous_selected = controls.selected;
            std::vector<uint32_t> nearby;
            query(controls.boat, controls.intermediate + controls.hysteresis, nearby);
            std::vector<uint32_t> camera_near;
            query(controls.camera, controls.intermediate + controls.hysteresis, camera_near);
            nearby.insert(nearby.end(), camera_near.begin(), camera_near.end());
            auto selected = code_slots.find(controls.selected);
            if (selected != code_slots.end())
                nearby.push_back(selected->second);
            for (auto i : nearby)
                if (animals[i].due > sim + .2 && detail(animals[i]) < animals[i].tier)
                    schedule(i, sim + .2);
        }
        if (controls.speed > 0) {
            while (!events.empty() && events.top().at <= requested && !stopping &&
                   seconds(Clock::now() - begin) * 1000 < clamp(controls.cpu_ms, 1, 40)) {
                Event e = events.top();
                events.pop();
                if (e.slot >= animals.size())
                    continue;
                auto &a = animals[e.slot];
                if (!a.alive || a.generation != e.generation || a.token != e.token)
                    continue;
                sim = std::max(sim, e.at);
                update(e.slot);
            }
            if (events.empty() || events.top().at > requested)
                sim = requested;
        }
        cpu_total += seconds(Clock::now() - begin) * 1000;
        if (seconds(Clock::now() - published_at) >= .05) {
            publish();
            published_at = Clock::now();
        }
        if (events.size() > animals.size() * 3) {
            std::priority_queue<Event> compact;
            for (uint32_t i = 0; i < animals.size(); i++) {
                auto const &a = animals[i];
                if (a.alive)
                    compact.push({a.due, i, a.generation, a.token});
            }
            events.swap(compact);
        }
        std::unique_lock<std::mutex> lock(mutex);
        cv.wait_for(lock, std::chrono::milliseconds(5), [&] { return stopping.load() || !commands.empty(); });
    }
    publish();
}
} // namespace bay
