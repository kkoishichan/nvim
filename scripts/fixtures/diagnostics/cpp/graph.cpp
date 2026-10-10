// Graph routing sample with deliberate diagnostics (clangd, -Wall -Wextra, C++20).
//
// Intended findings:
//   - unused variable / unused parameter / unused lambda capture
//   - comparison of integers of different signs
//   - narrowing conversion inside braces (error)
//   - use of undeclared identifier (error)
//   - calling a non-const member on a const object (error)
//   - no viable conversion / wrong argument type (error)
//   - non-void function does not return a value in all paths
//   - deprecated function use
//   - clang-analyzer: null dereference, use after free

#include <algorithm>
#include <cstdint>
#include <functional>
#include <iostream>
#include <limits>
#include <map>
#include <memory>
#include <optional>
#include <queue>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace routing {

using NodeId = std::uint32_t;
using Weight = double;

struct Edge {
    NodeId from;
    NodeId to;
    Weight weight;
    std::string label;
};

struct Node {
    NodeId id;
    std::string name;
    double latitude;
    double longitude;
};

class Graph {
public:
    void addNode(Node node)
    {
        if (nodes_.contains(node.id)) {
            throw std::invalid_argument("duplicate node " + std::to_string(node.id));
        }
        adjacency_[node.id];
        nodes_.emplace(node.id, std::move(node));
    }

    void addEdge(Edge edge)
    {
        requireNode(edge.from);
        requireNode(edge.to);
        adjacency_[edge.from].push_back(edge);
        edges_.push_back(std::move(edge));
    }

    const Node &node(NodeId id) const { return nodes_.at(id); }

    std::size_t nodeCount() const { return nodes_.size(); }

    std::size_t edgeCount() const { return edges_.size(); }

    const std::vector<Edge> &edgesFrom(NodeId id) const
    {
        static const std::vector<Edge> empty;
        auto found = adjacency_.find(id);
        return found == adjacency_.end() ? empty : found->second;
    }

    std::vector<NodeId> nodeIds() const
    {
        std::vector<NodeId> ids;
        ids.reserve(nodes_.size());
        for (const auto &[id, _] : nodes_) {
            ids.push_back(id);
        }
        return ids;
    }

    void pruneHeavier(Weight limit)
    {
        for (auto &[id, edges] : adjacency_) {
            std::erase_if(edges, [limit](const Edge &edge) { return edge.weight > limit; });
        }
        std::erase_if(edges_, [limit](const Edge &edge) { return edge.weight > limit; });
    }

    void rename(NodeId id, std::string name) { nodes_.at(id).name = std::move(name); }

private:
    void requireNode(NodeId id) const
    {
        if (!nodes_.contains(id)) {
            throw std::out_of_range("unknown node " + std::to_string(id));
        }
    }

    std::map<NodeId, Node> nodes_;
    std::unordered_map<NodeId, std::vector<Edge>> adjacency_;
    std::vector<Edge> edges_;
};

struct Route {
    std::vector<NodeId> path;
    Weight cost = 0;

    bool empty() const { return path.empty(); }
};

class Router {
public:
    explicit Router(const Graph &graph) : graph_(graph) {}

    std::optional<Route> shortest(NodeId from, NodeId to) const
    {
        std::unordered_map<NodeId, Weight> distance;
        std::unordered_map<NodeId, NodeId> previous;
        using Item = std::pair<Weight, NodeId>;
        std::priority_queue<Item, std::vector<Item>, std::greater<>> frontier;
        distance[from] = 0;
        frontier.emplace(0, from);
        while (!frontier.empty()) {
            auto [cost, current] = frontier.top();
            frontier.pop();
            if (current == to) {
                break;
            }
            if (cost > distance[current]) {
                continue;
            }
            for (const Edge &edge : graph_.edgesFrom(current)) {
                Weight candidate = cost + edge.weight;
                auto known = distance.find(edge.to);
                if (known == distance.end() || candidate < known->second) {
                    distance[edge.to] = candidate;
                    previous[edge.to] = current;
                    frontier.emplace(candidate, edge.to);
                }
            }
        }
        if (!distance.contains(to)) {
            return std::nullopt;
        }
        Route route;
        route.cost = distance[to];
        for (NodeId cursor = to;; cursor = previous[cursor]) {
            route.path.push_back(cursor);
            if (cursor == from) {
                break;
            }
        }
        std::reverse(route.path.begin(), route.path.end());
        return route;
    }

    std::vector<NodeId> reachable(NodeId from) const
    {
        std::vector<NodeId> order;
        std::set<NodeId> seen{from};
        std::queue<NodeId> pending;
        pending.push(from);
        while (!pending.empty()) {
            NodeId current = pending.front();
            pending.pop();
            order.push_back(current);
            for (const Edge &edge : graph_.edgesFrom(current)) {
                if (seen.insert(edge.to).second) {
                    pending.push(edge.to);
                }
            }
        }
        return order;
    }

    int degree(NodeId id) const
    {
        int count = 0;
        const auto &edges = graph_.edgesFrom(id);
        for (int i = 0; i < edges.size(); ++i) { // diag: signed/unsigned comparison
            if (edges[i].weight > 0) {
                ++count;
            }
        }
        return count;
    }

private:
    const Graph &graph_;
};

std::string describe(const Route &route, const Graph &graph)
{
    std::ostringstream out;
    for (std::size_t i = 0; i < route.path.size(); ++i) {
        if (i > 0) {
            out << " -> ";
        }
        out << graph.node(route.path[i]).name;
    }
    out << " (" << route.cost << ")";
    return out.str();
}

[[deprecated("use describe(const Route&, const Graph&)")]]
std::string describeLegacy(const Route &route)
{
    std::ostringstream out;
    for (NodeId id : route.path) {
        out << id << ' ';
    }
    return out.str();
}

Weight averageWeight(const Graph &graph)
{
    Weight total = 0;
    std::size_t count = 0;
    for (NodeId id : graph.nodeIds()) {
        for (const Edge &edge : graph.edgesFrom(id)) {
            total += edge.weight;
            ++count;
        }
    }
    int unusedBuckets = 4; // diag: unused variable
    return count == 0 ? 0 : total / static_cast<Weight>(count);
}

std::optional<NodeId> hub(const Graph &graph, int minimumDegree)
{
    Router router(graph);
    for (NodeId id : graph.nodeIds()) {
        if (router.degree(id) >= minimumDegree) {
            return id;
        }
    }
    // diag: non-void function does not return a value in all control paths
}

std::vector<Edge> heaviest(const Graph &graph, std::size_t limit)
{
    std::vector<Edge> all;
    for (NodeId id : graph.nodeIds()) {
        const auto &edges = graph.edgesFrom(id);
        all.insert(all.end(), edges.begin(), edges.end());
    }
    std::sort(all.begin(), all.end(), [](const Edge &a, const Edge &b) { return a.weight > b.weight; });
    if (all.size() > limit) {
        all.resize(limit);
    }
    return all;
}

Node makeNode(NodeId id, std::string_view name, double latitude, double longitude)
{
    long raw = static_cast<long>(latitude * 1000);
    Node node{id, std::string(name), raw, longitude}; // diag: narrowing long -> double in braces
    return node;
}

void relabel(const Graph &graph, NodeId id)
{
    graph.rename(id, "renamed"); // diag: non-const member on const reference
}

Weight totalCost(const std::vector<Route> &routes)
{
    Weight total = 0;
    std::for_each(routes.begin(), routes.end(), [&total, &routes](const Route &route) { // diag: unused capture routes
        total += route.cost;
    });
    return total;
}

std::string summary(const Graph &graph, int verbosity)
{
    std::ostringstream out;
    out << graph.nodeCount() << " nodes, " << graph.edgeCount() << " edges";
    out << ", avg weight " << averageWeigth(graph); // diag: undeclared identifier
    return out.str();
}

Route *pickRoute(std::vector<Route> &routes, std::size_t index)
{
    Route *selected = nullptr;
    if (index < routes.size()) {
        selected = &routes[index];
    }
    selected->cost += 1; // diag: analyzer, null dereference when index is out of range
    return selected;
}

std::string firstLabel(const Graph &graph, NodeId id)
{
    auto *copy = new std::vector<Edge>(graph.edgesFrom(id));
    std::string label = copy->empty() ? "" : copy->front().label;
    delete copy;
    return copy->empty() ? label : label + "!"; // diag: analyzer, use after free
}

Graph buildDemo()
{
    Graph graph;
    graph.addNode(makeNode(1, "Depot", 52.52, 13.405));
    graph.addNode(makeNode(2, "Harbour", 53.55, 9.993));
    graph.addNode(makeNode(3, "Mill", 51.34, 12.37));
    graph.addNode(makeNode(4, "Market", 50.11, 8.68));
    graph.addNode(makeNode(5, "Quarry", 48.14, 11.58));
    graph.addEdge({1, 2, 290.0, "A24"});
    graph.addEdge({1, 3, 190.0, "A9"});
    graph.addEdge({3, 4, 390.0, "A4"});
    graph.addEdge({2, 4, 490.0, "A7"});
    graph.addEdge({4, 5, 400.0, "A3"});
    graph.addEdge({3, 5, 430.0, "A93"});
    graph.addEdge({5, 1, 585.0, "A9"});
    return graph;
}

int runDemo()
{
    Graph graph = buildDemo();
    Router router(graph);
    auto route = router.shortest(1, 5);
    if (!route) {
        std::cerr << "no route\n";
        return 1;
    }
    std::cout << describe(*route, graph) << '\n';
    std::cout << describeLegacy(*route) << '\n'; // diag: deprecated
    std::cout << summary(graph, "verbose") << '\n'; // diag: no viable conversion from string literal to int
    for (const Edge &edge : heaviest(graph, 3)) {
        std::cout << edge.label << ' ' << edge.weight << '\n';
    }
    std::vector<Route> routes{*route};
    std::cout << totalCost(routes) << ' ' << pickRoute(routes, 0)->cost << '\n';
    return 0;
}

} // namespace routing
