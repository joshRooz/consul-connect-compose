# Mesh Transit

## Local
```mermaid
flowchart LR;
                                                                                                                                     
a["A"]
subgraph dc1["DC1"]
  subgraph dc1-default["default"]
    ing["API GW"]
    egr["TGW"]
  end
end
b["B"]

a-->ing-->egr-->b
```

## Partition
```mermaid
flowchart LR;
                                                                                                                                     
a["A"]
subgraph dc1["DC1"]
  subgraph dc1-default["default"]
    ing["API GW"]
  end

  subgraph dc1-alpha["alpha"]
    egr["TGW"]
  end   
end
b["B"]

a-->ing-->egr-->b
```

## Peer
```mermaid
flowchart LR;

a["A"]
subgraph dc1["DC1"]
  subgraph dc1-default["default"]
    ing["API GW"]
  end
end

subgraph dc2["DC2"]
  subgraph dc2-default["default"]
    egr["TGW"]
  end
end
b["B"]

a-->ing-->egr-->b
```

