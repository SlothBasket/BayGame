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
        check(competition.animals[1].misses + competition.animals[2].misses == 0, "lost target counted as miss");
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
        std::cout << "PASS conservation, rejoining, escape cap, stable handles, one-time consumption, route "
                     "continuity, event-clock invariance\n";
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
