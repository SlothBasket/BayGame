#include "src/ecosystem.hpp"
#include <iostream>
#include <stdexcept>
namespace bay {
struct EngineTest {
    static void check(bool value, const char *reason) {
        if (!value)
            throw std::runtime_error(reason);
    }
    static void setup(Engine &e) {
        e.width = 32;
        e.height = 32;
        e.cell = 32;
        e.water.assign(1024, 1);
        Node n;
        n.at = {256, 256};
        n.depth = 3;
        n.neighbors = {};
        e.nodes.push_back(n);
        Animal school;
        school.kind = 1;
        school.id = 100;
        school.index = 0;
        school.species = 1;
        school.at = {256, 256};
        school.home = school.feeding = 0;
        school.quantity = school.capacity = 30;
        school.size = 5;
        school.depth = .8;
        e.animals.push_back(school);
        Controls c;
        c.speed = 0;
        c.boat = c.camera = {256, 256};
        e.control(c);
        e.start(18472);
        e.stop();
        e.controls = c;
        e.controls.speed = 1;
        e.sim = 0;
        e.requested = 0;
        while (!e.events.empty())
            e.events.pop();
        e.schedule(0, .2);
    }
    static void until(Engine &e, double end) {
        while (!e.events.empty() && e.events.top().at <= end) {
            auto event = e.events.top();
            e.events.pop();
            auto &a = e.animals[event.slot];
            if (!a.alive || a.generation != event.generation || a.token != event.token)
                continue;
            e.sim = event.at;
            e.update(event.slot);
        }
        e.sim = end;
    }
    static int units(Engine const &e) {
        int total = 0;
        for (auto const &a : e.animals)
            if (a.alive && a.kind == 1)
                total += a.quantity;
        return total;
    }
    static void run() {
        Engine e;
        setup(e);
        e.detach_min = e.detach_max = 2;
        e.detach_interval = 4;
        e.scatter(0, {258, 256});
        e.sim = 5;
        e.scatter(0, {258, 256});
        e.sim = 10;
        e.scatter(0, {258, 256});
        e.sim = 15;
        e.scatter(0, {258, 256});
        check(e.animals[0].escapees == 6, "escapee cap");
        check(units(e) == 30, "detach conservation");
        uint32_t child = 1;
        auto old = e.handle(child);
        check(e.eat(child), "consume");
        check(!e.eat(child), "double consumption");
        check(units(e) == 29, "consume conservation");
        Animal replacement;
        replacement.kind = 1;
        replacement.individual = true;
        replacement.quantity = 1;
        replacement.id = 0;
        replacement.at = {256, 256};
        replacement.node = 0;
        auto recycled = e.add_bait(replacement);
        check(recycled == child, "slot recycling");
        check(!e.valid(old), "stale generation accepted");
        check(e.animals[recycled].id != 101, "reused identity");
        e.bait(recycled, .2);
        check(e.animals[recycled].hunger == 0, "isolated prey has feeding drive");
        e.retire(recycled);
        // Put survivors safely at their parent's current position, then run actual regroup logic.
        e.animals[0].threat_until = 0;
        e.animals[0].fear = 0;
        e.animals[0].path.clear();
        for (uint32_t i = 1; i < e.animals.size(); i++) {
            auto &a = e.animals[i];
            if (!a.alive)
                continue;
            a.at = e.animals[0].at;
            a.path.clear();
            a.threat_until = 0;
            a.regroup_at = 0;
            a.depth = e.animals[0].depth;
            e.bait(i, .2);
        }
        check(e.animals[0].quantity == 29 && e.animals[0].escapees == 0, "rejoin conservation");
        check(e.rejoined == 5, "return count");
        // Distant travel must have a continuous analytic midpoint, not a detail-tier jump.
        auto &a = e.animals[0];
        a.at = {256, 256};
        e.sim = 20;
        e.route(a, {286, 256}, 0, 1);
        auto midpoint = e.position(a, 35);
        check(std::abs(midpoint.x - 271) < 1e-8, "analytic travel");
        a.tier = 2;
        e.sim = 35;
        e.advance(a, 35);
        auto same = a.at;
        a.tier = 0;
        check((same - midpoint).len() < 1e-8, "tier continuity");
        Engine competition;
        setup(competition);
        competition.animals[0].quantity = 1;
        competition.animals[0].individual = true;
        competition.hit_min = competition.hit_max = 1;
        Animal predator;
        predator.at = competition.animals[0].at;
        predator.depth = competition.animals[0].depth;
        predator.target = competition.handle(0);
        predator.node = 0;
        competition.animals.push_back(predator);
        competition.animals.push_back(predator);
        competition.attack(1);
        competition.attack(2);
        check(competition.consumed == 1, "competing predators duplicated prey");
        check(competition.animals[1].captures + competition.animals[2].captures == 1, "capture count");
        check(competition.animals[1].misses + competition.animals[2].misses == 0,
              "lost target counted as miss");
        competition.water[8 * competition.width + 9] = 0;
        check(!competition.clear({256, 272}, {320, 272}), "land shortcut accepted");
        Engine first, second;
        setup(first);
        setup(second);
        until(first, 60);
        for (int i = 1; i <= 60; i++)
            until(second, i);
        check(first.event_count == second.event_count, "speed changes skipped events");
        check((first.position(first.animals[0], 60) - second.position(second.animals[0], 60)).len() < 1e-7,
              "speed changed trajectory");

        Engine ecology;
        setup(ecology);
        check(!ecology.eat(0), "ordinary pod directly edible");
        ecology.animals[0].quantity = 1;
        check(!ecology.eat(0), "quantity changed prey type exception");
        ecology.animals[0].quantity = 30;
        Animal hunter;
        hunter.motivated = true; // Synthetic hungry actor bypasses Engine::start().
        hunter.id = 99;
        hunter.kind = 0;
        hunter.species = 2;
        hunter.index = 0;
        hunter.node = 0;
        hunter.at = {248, 256};
        hunter.depth = .8;
        hunter.size = 50;
        hunter.heading = {1, 0};
        hunter.profile.detect = 30;
        hunter.profile.reach = 2;
        hunter.profile.burst = 2;
        hunter.target = ecology.handle(0);
        ecology.animals.push_back(hunter);
        ecology.query_marks.push_back(0);
        ecology.occupancy(1);
        auto &h = ecology.animals[1];
        auto &pod = ecology.animals[0];
        check(ecology.senses(h, pod), "ahead prey not detected");
        h.heading = {-1, 0};
        check(!ecology.senses(h, pod), "rear distant prey detected");
        h.at = {254, 256};
        check(ecology.senses(h, pod), "close rear awareness missing");
        h.at = {248, 256};
        h.heading = {1, 0};
        ecology.hunt(1, .2);
        check(pod.escapees == 0, "passive detection fragmented pod");
        h.at = {252, 256};
        h.path.clear();
        h.sync_time = ecology.sim;
        ecology.hunt(1, .2);
        check(pod.escapees >= 1 && pod.escapees <= 3, "credible approach did not detach a handful");
        check(h.attempts == 0 && h.misses == 0 && h.captures == 0, "school pressure counted as attack");
        check(units(ecology) == 30, "pressure duplicated prey");
        auto edible = ecology.acquire(1);
        check(ecology.valid(edible) && ecology.animals[edible.slot].individual,
              "school preferred over straggler");
        auto before = pod.escapees;
        for (int k = 0; k < 10; k++)
            ecology.scatter(0, h.at);
        check(pod.escapees == before, "multiple predators bypassed shared cooldown");
        ecology.bait(0, .2);
        check(pod.state == 10 && pod.route_speed > .5, "school did not flee cohesively");
        uint32_t escaped = edible.slot;
        ecology.sim = 10;
        pod.path.clear();
        pod.at = {260, 256};
        pod.threat_until = 0;
        auto &survivor = ecology.animals[escaped];
        survivor.path.clear();
        survivor.at = pod.at;
        survivor.depth = pod.depth;
        survivor.threat_until = 0;
        survivor.regroup_at = 0;
        ecology.bait(escaped, .2);
        check(!survivor.alive && ecology.rejoined == 1, "safe survivor did not rejoin moving parent");
        Animal orphan;
        orphan.kind = 1;
        orphan.species = 1;
        orphan.individual = orphan.temporary = true;
        orphan.parent_id = 999999;
        orphan.at = pod.at;
        orphan.depth = pod.depth;
        orphan.node = 0;
        auto orphan_slot = ecology.add_bait(orphan);
        ecology.bait(orphan_slot, .2);
        check(!ecology.animals[orphan_slot].alive && ecology.rejoined == 2, "orphan adoption/rejoin failed");
        orphan.species = 7;
        orphan.at = {400, 400};
        orphan.parent_id = 999999;
        orphan_slot = ecology.add_bait(orphan);
        ecology.bait(orphan_slot, .2);
        check(ecology.animals[orphan_slot].alive && ecology.animals[orphan_slot].state == 14 &&
                  ecology.animals[orphan_slot].hunger == 0,
              "orphan without school did not shelter");

        Engine encounter;
        setup(encounter);
        encounter.hit_min = encounter.hit_max = 1;
        hunter.at = {250, 256};
        hunter.heading = {1, 0};
        hunter.target = encounter.handle(0);
        hunter.profile.burst = 3;
        encounter.animals.push_back(hunter);
        encounter.query_marks.push_back(0);
        encounter.occupancy(1);
        encounter.schedule(1, .1);
        until(encounter, 40);
        check(encounter.detached > 0 && encounter.animals[1].captures > 0,
              "scheduled approach/pursuit did not capture a straggler");
        check(units(encounter) + int(encounter.consumed) == 30, "scheduled encounter conservation");
        check(encounter.animals[0].escapees <= 6, "scheduled encounter cap");
        Engine last_member;
        setup(last_member);
        last_member.animals[0].quantity = 1;
        last_member.scatter(0, {258, 256});
        check(last_member.animals[0].quantity == 0 && last_member.animals[0].escapees == 1,
              "last school member cannot break away");
        Engine fry;
        setup(fry);
        fry.animals[0].species = 0;
        fry.scatter(0, {258, 256});
        check(fry.animals.size() == 1, "fry detached");
        check(fry.eat(0) && fry.animals[0].quantity == 29, "fry direct consumption failed");
        Engine smooth;
        setup(smooth);
        auto &moving = smooth.animals[0];
        moving.individual = true;
        moving.velocity = {1, 0};
        smooth.steer(moving, {280, 256}, .2, 1);
        check(std::abs(moving.at.x - 256) < 1e-8 && smooth.position(moving, .1).x > 256,
              "steering jumped instead of publishing trajectory");
        smooth.sim = 1;
        smooth.animals[0].path.clear();
        smooth.animals[0].shelter_hold = .5;
        smooth.shelter(smooth.animals[0]);
        for (size_t k = 1; k < smooth.animals[0].path.size(); k++)
            check(smooth.clear(smooth.animals[0].path[k - 1], smooth.animals[0].path[k]),
                  "shelter route crossed land");

        Engine coast; setup(coast);
        coast.nodes[0].shore=10;coast.nodes[0].neighbors={1,2};
        Node open,edge,end;
        open.at={320,256};open.shore=1000;open.neighbors={0,3};
        edge.at={320,288};edge.shore=10;edge.neighbors={0,3};
        end.at={384,256};end.shore=10;end.neighbors={1,2};
        coast.nodes.push_back(open);coast.nodes.push_back(edge);coast.nodes.push_back(end);
        coast.costs.resize(4);coast.parents.resize(4);coast.visited.resize(4);
        for(int i=1;i<4;i++) coast.node_cells[0x100000001LL].push_back(i);
        coast.route(coast.animals[0],end.at,3,.5);
        bool passed_edge=false;
        for(auto point:coast.animals[0].path) if((point-edge.at).len()<.01) passed_edge=true;
        check(passed_edge,"coastal school took open-water shortcut");
        for(size_t k=1;k<coast.animals[0].path.size();k++) check(coast.clear(coast.animals[0].path[k-1],coast.animals[0].path[k]),"coastal path not water valid");
        std::cout << "PASS conservation, rejoining, escape cap, stable handles, one-time consumption, route "
                     "continuity, event-clock invariance, school pressure, prey priority, directional "
                     "senses, fry exception, orphan survival, smooth steering\n";
    }
};
} // namespace bay
int main() {
    try {
        bay::EngineTest::run();
        return 0;
    } catch (std::exception const &e) {
        std::cerr << "FAIL " << e.what() << "\n";
        return 1;
    }
}
