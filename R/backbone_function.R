#' Backbone layout graph layout
#'
#' @param g igraph object
#' @param keep fraction of edges to keep
#' @param backbone logical. Return edge ids of the backbone
#'
#' @return coordinates to be used layouting a graph
#' @export
#'

backbone_layout <- function(g,keep=0.2,backbone=T){
  # orbs <- oaqc::oaqc(igraph::get.edgelist(g,names = F)-1,non_ind_freq = T)
  # qu <- orbs$n_orbits_non_ind[,17]
  # el <- igraph::get.edgelist(g)
  # el <- cbind(el,orbs$e_orbits_non_ind[,11])
  # w <- apply(el,1,function(x) x[3]/sqrt(qu[x[1]]*qu[x[2]]))
  #weighting ----
  orbs <- oaqc::oaqc(igraph::get.edgelist(g,names = F)-1,non_ind_freq = T)
  e11 <- orbs$e_orbits_non_ind[,11]
  qu <- rep(0,igraph::vcount(g))
  el <- igraph::get.edgelist(g,names=F)
  el <- cbind(el,e11)
  for(e in 1:nrow(el)){
    qu[el[e,1]] <- qu[el[e,1]]+el[e,3]
    qu[el[e,2]] <- qu[el[e,2]]+el[e,3]
  }
  w <- apply(el,1,function(x) x[3]/sqrt(qu[x[1]]*qu[x[2]]))

  w[is.na(w)] <- 0
  w[is.infinite(w)] <- 0
  igraph::E(g)$weight <- w
  #reweighting -----
  w <- max_prexif_jaccard(g)
  igraph::E(g)$weight <- w
  #filtering ----
  igraph::E(g)$bone <- w>=sort(w,decreasing=T)[ceiling(igraph::ecount(g)*keep)]
  g_umst <- umst(g)
  g_bone <- igraph::graph_from_edgelist(el[igraph::E(g)$bone,1:2],directed = F)
  g_lay <- igraph::simplify(igraph::graph.union(g_umst,g_bone))
  if(backbone){
    bb <- backbone_edges(g,g_lay)
  } else {
    bb <- NULL
  }
  xy <- smglr::stress_majorization(g_lay)
  list(xy=xy,backbone=bb)
}

#-------------------------------------------------------------------------------
# helper functions
#-------------------------------------------------------------------------------

umst <- function(g){
  el <- igraph::get.edgelist(g)
  el <- cbind(el,igraph::E(g)$weight)
  el <- el[order(el[,3],decreasing=T),]
  el <- cbind(el,rank(-el[,3]))
  vfind <- 1:igraph::vcount(g)
  el_un <- matrix(0,0,2)
  for(i in unique(el[,4])){
    el_tmp <- matrix(0,0,2)
    Bi <- which(el[,4]==i)
    for(e in Bi){
      u <- el[e,1]
      v <- el[e,2]
      if(vfind[u]!=vfind[v]){
        el_tmp <- rbind(el_tmp,c(u,v))
      }
    }
    for(e in nrow(el_tmp)){
      u <- el_tmp[e,1]
      v <- el_tmp[e,2]
      partu <- vfind[u]
      partv <- vfind[v]
      vfind[v] <- partu
      vfind[vfind==partv] <- partu
    }
    el_un <- rbind(el_un,el_tmp)
  }
  return(igraph::simplify(igraph::graph_from_edgelist(el_un,directed=F)))
}


backbone_edges <- function(g,g_lay){
  tmp <- rbind(igraph::get.edgelist(g_lay),igraph::get.edgelist(g))
  which(duplicated(tmp))-igraph::ecount(g_lay)
}

max_prexif_jaccard <- function(g){
  el <- igraph::get.edgelist(g)
  deg <- igraph::degree(g)
  # el <- cbind(el,igraph::E(g)$weight)
  Tuv <- neighbors_overlap(g)
  Sset <- matrix(0,sum(unlist(lapply(Tuv,length))),2)
  ranks <- neighbors_rank(g)
  N_ranks <- ranks$N_ranks
  si_ranks <- ranks$si_ranks
  k <- 0
  omega <- rep(0,igraph::ecount(g))
  vis <- rep(0,igraph::ecount(g))
  for(e in 1:nrow(el)){
    u <- el[e,1]
    v <- el[e,2]
    for(i in seq_along(Tuv[[e]])){
      k <- k+1
      w <- Tuv[[e]][i]
      idu <- which(N_ranks[[u]][,1]==w)
      idv <- which(N_ranks[[v]][,1]==w)
      ruw <- N_ranks[[u]][idu,2]
      rvw <- N_ranks[[v]][idv,2]
      Sset[k,1] <- max(ruw,rvw)
      Sset[k,2] <- e
    }
  }
  Sset <- Sset[order(Sset[,1],decreasing = F),]
  for(i in 1:nrow(Sset)){
    vis[Sset[i,2]] <- vis[Sset[i,2]] + 1
    u <- el[Sset[i,2],1]
    v <- el[Sset[i,2],2]
    s_rku <- min(si_ranks[[u]][Sset[i,1]+1],deg[u],na.rm=T)
    s_rkv <- min(si_ranks[[v]][Sset[i,1]+1],deg[v],na.rm=T)
    omega[Sset[i,2]] <- max(omega[Sset[i,2]],vis[Sset[i,2]]/(s_rku+s_rkv),na.rm=T)
  }
  omega
}

neighbors_rank <- function(g){
  N_ranks <- vector("list",igraph::vcount(g))
  si_ranks <- vector("list",igraph::vcount(g))
  for(u in 1:igraph::vcount(g)){
    Nu <- igraph::incident(g,u)
    Nu_edges <- igraph::ends(g,Nu,names = F)
    eids <- igraph::get.edge.ids(g,c(t(Nu_edges)))
    omega <- igraph::E(g)$weight[eids]
    Nu <- setdiff(c(Nu_edges),u)
    r <- rank(-omega)
    r <- match(r, sort(unique(r)))-1
    N_ranks[[u]] <- cbind(Nu,r)
    # N_ranks[[u]] <- N_ranks[[u]][order(N_ranks[[u]][,2]),]
    si_ranks[[u]] <- cumsum(unname(table(r)))
  }
  list(N_ranks=N_ranks,si_ranks=si_ranks)
}

neighbors_overlap <- function(g){
  Tuv <- vector("list",igraph::ecount(g))
  el <- igraph::get.edgelist(g,names = F)
  for(e in 1:nrow(el)){
    Nu <- igraph::neighborhood(g,1,el[e,1],mindist = 1)[[1]]
    Nv <- igraph::neighborhood(g,1,el[e,2],mindist = 1)[[1]]
    Tuv[[e]] <- intersect(Nu,Nv)
  }
  Tuv
}
