---@class Queue
Queue = {
    First = 0,
    Last = -1,
}

function Queue.__index(table, key)
    return Queue[key]
end

function Queue:Add(value)
    local last = self.Last + 1
    self.Last = last
    self.List[last] = value
end

function Queue:AddFirst(value)
    local first = self.First - 1
    self.First = first
    self.List[first] = value
end

function Queue:Remove()
    local first = self.First
    if first > self.Last then
        --list is empty
        return nil
    end
    local value = self.List[first]
    self.List[first] = nil -- to allow garbage collection
    self.First = first + 1
    return value
end

function Queue:Get()
    return self.List[self.First]
end

function Queue.new()
    local obj = {List = {}}
    setmetatable(obj, Queue)
    return obj
end
