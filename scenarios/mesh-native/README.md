# Mesh Transit

## Local
```mermaid
flowchart LR;

subgraph dc1["DC1"]
  subgraph dc1-default["default"]
    a["A"]
    b["B"]
  end
end

a-->b
```

## Partition
```mermaid
flowchart TB;

subgraph dc1["DC1"]
  subgraph dc1-default["default"]
    a["A"]
  end 

  subgraph dc1-alpha["alpha"]
    b["B"]
  end   
end

a-->b
```

## Peer
```mermaid
flowchart LR;

subgraph dc1["DC1"]
  subgraph dc1-default["default"]
    a["A"]
  end
end

subgraph dc2["DC2"]
  subgraph dc2-default["default"]
    b["B"]  
  end 
end

a-->b
```
