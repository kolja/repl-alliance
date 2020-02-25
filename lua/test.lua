
local tt = {"foo", "bar", "baz", "bongo", "bra", "boo"}
local result = "->"
for i,v in ipairs(tt) do
    if v == "bongo" then
        result = i
    end
end
print(result)
