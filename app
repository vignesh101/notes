properties.put("group.initial.rebalance.delay.ms", "0");     // No delay for consumer join
properties.put("metadata.max.age.ms", "500");                // Faster metadata refresh
properties.put("offsets.topic.replication.factor", "1");
properties.put("transaction.state.log.replication.factor", "1");
properties.put("transaction.state.log.min.isr", "1");
properties.put("num.partitions", "1");                       // If not already set
properties.put("auto.create.topics.enable", "true");